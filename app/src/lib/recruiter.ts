export function normalizeCompany(value: string): string {
  return value.normalize('NFKC').trim().replace(/\s+/g, ' ');
}

export function validCompany(value: string): boolean {
  const normalized = normalizeCompany(value);
  return (
    normalized.length >= 2 &&
    normalized.length <= 120 &&
    ![...normalized].some((character) => {
      const code = character.codePointAt(0)!;
      return code < 32 || code === 127;
    })
  );
}
