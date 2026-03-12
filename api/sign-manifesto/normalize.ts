/**
 * Normalizes an email address for deduplication.
 * - Lowercases the entire email
 * - Strips dots from the local part
 * - Strips '+' and everything after it from the local part
 */
export function normalizeEmail(email: string): string {
  const [localPart, domain] = email.toLowerCase().split("@");
  if (!localPart || !domain) {
    throw new Error("Invalid email format");
  }

  const withoutPlus = localPart.split("+")[0];
  const withoutDots = withoutPlus.replace(/\./g, "");

  return `${withoutDots}@${domain}`;
}

/**
 * Basic email validation — checks format, not deliverability.
 */
export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}
