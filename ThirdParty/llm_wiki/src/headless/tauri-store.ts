class HeadlessStore {
  private values = new Map<string, unknown>()

  async get<T>(key: string): Promise<T | undefined> {
    return this.values.get(key) as T | undefined
  }

  async set(key: string, value: unknown): Promise<void> {
    this.values.set(key, value)
  }

  async delete(key: string): Promise<void> {
    this.values.delete(key)
  }

  async save(): Promise<void> {}
}

export async function load(): Promise<HeadlessStore> {
  return new HeadlessStore()
}
