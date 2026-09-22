import { describe, it, expect } from 'vitest';
import { normalizeCompany, validCompany } from '../../app/src/lib/recruiter';
describe('company validation', () => {
  it('normalizes spacing and unicode', () =>
    expect(normalizeCompany('  ＡＣＭＥ  Labs ')).toBe('ACME Labs'));
  it('rejects empty, oversized, and control character input', () => {
    for (const input of [' ', 'a', 'a'.repeat(121), 'ab\u0000cd'])
      expect(validCompany(input)).toBe(false);
    expect(validCompany('Example & Co.')).toBe(true);
  });
});
