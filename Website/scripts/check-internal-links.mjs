import { access, readdir, readFile, stat } from "node:fs/promises";
import { dirname, join, normalize, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const outputDirectory = resolve(process.argv[2] ?? join(repositoryRoot, ".build/site"));
const hostingBasePath = "/docs/taskloom-swift";
const attributePattern = /\b(?:href|src)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi;

const htmlFiles = [];
const failures = [];

async function collectHTMLFiles(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        const entryPath = join(directory, entry.name);
        if (entry.isDirectory()) {
            await collectHTMLFiles(entryPath);
        } else if (entry.isFile() && entry.name.endsWith(".html")) {
            htmlFiles.push(entryPath);
        }
    }
}

function isExternal(reference) {
    return (
        reference.startsWith("#") ||
        reference.startsWith("//") ||
        /^[a-z][a-z0-9+.-]*:/i.test(reference)
    );
}

function pageDirectory(sourceFile) {
    const sourceRelativePath = relative(outputDirectory, sourceFile);
    return sourceRelativePath.endsWith("/index.html") || sourceRelativePath === "index.html"
        ? dirname(sourceRelativePath)
        : dirname(sourceRelativePath);
}

function resolveReference(sourceFile, reference) {
    const referencePath = decodeURIComponent(reference.split(/[?#]/, 1)[0]);
    if (referencePath.startsWith("/")) {
        if (referencePath !== hostingBasePath && !referencePath.startsWith(`${hostingBasePath}/`)) {
            throw new Error(`does not use the ${hostingBasePath} hosting base path`);
        }
        return referencePath.slice(hostingBasePath.length).replace(/^\//, "");
    }

    return normalize(join(pageDirectory(sourceFile), referencePath));
}

function isWithinOutputDirectory(candidate) {
    const candidateRelativePath = relative(outputDirectory, candidate);
    return (
        candidateRelativePath === "" ||
        (!candidateRelativePath.startsWith(`..${sep}`) && candidateRelativePath !== "..")
    );
}

async function exists(path) {
    try {
        await access(path);
        return true;
    } catch {
        return false;
    }
}

async function resolvesToSiteContent(referencePath) {
    const candidate = resolve(outputDirectory, referencePath || ".");
    if (!isWithinOutputDirectory(candidate)) {
        return false;
    }

    if (await exists(candidate)) {
        const candidateStatus = await stat(candidate);
        if (candidateStatus.isFile()) {
            return true;
        }
        if (candidateStatus.isDirectory() && (await exists(join(candidate, "index.html")))) {
            return true;
        }
    }

    if (!referencePath.endsWith("/") && (await exists(`${candidate}.html`))) {
        return true;
    }

    if (await exists(join(candidate, "index.html"))) {
        return true;
    }

    return false;
}

await collectHTMLFiles(outputDirectory);

for (const sourceFile of htmlFiles) {
    const source = await readFile(sourceFile, "utf8");
    for (const match of source.matchAll(attributePattern)) {
        const reference = match[1] ?? match[2] ?? match[3];
        if (!reference || isExternal(reference)) {
            continue;
        }

        try {
            const referencePath = resolveReference(sourceFile, reference);
            if (!(await resolvesToSiteContent(referencePath))) {
                failures.push(`${relative(outputDirectory, sourceFile)} -> ${reference}`);
            }
        } catch (error) {
            failures.push(`${relative(outputDirectory, sourceFile)} -> ${reference} (${error.message})`);
        }
    }
}

if (failures.length > 0) {
    console.error("Broken internal links:");
    for (const failure of failures) {
        console.error(`  ${failure}`);
    }
    process.exitCode = 1;
} else {
    console.log(`Checked ${htmlFiles.length} HTML files in ${outputDirectory}.`);
}
