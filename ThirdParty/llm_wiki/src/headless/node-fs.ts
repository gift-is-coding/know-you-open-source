import fs from "node:fs/promises"
import path from "node:path"
import type { FileNode, WikiProject } from "@/types/wiki"

async function buildTree(dir: string): Promise<FileNode[]> {
  let entries
  try {
    entries = await fs.readdir(dir, { withFileTypes: true })
  } catch {
    return []
  }

  const nodes: FileNode[] = []
  for (const entry of entries) {
    const full = path.join(dir, entry.name).replace(/\\/g, "/")
    if (entry.isDirectory()) {
      nodes.push({
        name: entry.name,
        path: full,
        is_dir: true,
        children: await buildTree(full),
      } as FileNode)
    } else {
      nodes.push({
        name: entry.name,
        path: full,
        is_dir: false,
        children: [],
      } as FileNode)
    }
  }
  return nodes
}

export async function readFile(filePath: string): Promise<string> {
  return fs.readFile(filePath, "utf-8")
}

export async function writeFile(filePath: string, contents: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true })
  await fs.writeFile(filePath, contents, "utf-8")
}

export async function listDirectory(dirPath: string): Promise<FileNode[]> {
  return buildTree(dirPath)
}

export async function copyFile(source: string, destination: string): Promise<void> {
  await fs.mkdir(path.dirname(destination), { recursive: true })
  await fs.copyFile(source, destination)
}

export async function preprocessFile(filePath: string): Promise<string> {
  return fs.readFile(filePath, "utf-8")
}

export async function deleteFile(filePath: string): Promise<void> {
  await fs.rm(filePath, { force: true })
}

export async function findRelatedWikiPages(): Promise<string[]> {
  return []
}

export async function createDirectory(dirPath: string): Promise<void> {
  await fs.mkdir(dirPath, { recursive: true })
}

export async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath)
    return true
  } catch {
    return false
  }
}

export interface FileBase64 {
  base64: string
  mimeType: string
}

export async function readFileAsBase64(filePath: string): Promise<FileBase64> {
  const buffer = await fs.readFile(filePath)
  return {
    base64: buffer.toString("base64"),
    mimeType: "application/octet-stream",
  }
}

export async function createProject(name: string, projectPath: string): Promise<WikiProject> {
  await fs.mkdir(projectPath, { recursive: true })
  return {
    id: projectPath,
    name,
    path: projectPath,
  }
}

export async function openProject(projectPath: string): Promise<WikiProject> {
  return {
    id: projectPath,
    name: path.basename(projectPath),
    path: projectPath,
  }
}

export async function clipServerStatus(): Promise<string> {
  return "headless"
}

export async function knowYouProjectPath(): Promise<string | null> {
  return null
}
