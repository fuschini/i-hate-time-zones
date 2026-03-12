import { describe, it, expect } from "vitest";
import { normalizeEmail, isValidEmail } from "../normalize";

describe("normalizeEmail", () => {
  it("lowercases the entire email", () => {
    expect(normalizeEmail("John@Gmail.COM")).toBe("john@gmail.com");
  });

  it("strips dots from the local part", () => {
    expect(normalizeEmail("j.o.h.n@gmail.com")).toBe("john@gmail.com");
  });

  it("strips + tags from the local part", () => {
    expect(normalizeEmail("john+newsletter@gmail.com")).toBe("john@gmail.com");
  });

  it("handles dots and + tags together", () => {
    expect(normalizeEmail("j.o.h.n+test@gmail.com")).toBe("john@gmail.com");
  });

  it("does not strip dots from the domain", () => {
    expect(normalizeEmail("john@sub.domain.com")).toBe("john@sub.domain.com");
  });

  it("handles email with no dots or tags", () => {
    expect(normalizeEmail("simple@example.com")).toBe("simple@example.com");
  });

  it("strips dots from non-Gmail domains too (MVP behavior)", () => {
    expect(normalizeEmail("j.doe@yahoo.com")).toBe("jdoe@yahoo.com");
  });

  it("handles + with nothing after it", () => {
    expect(normalizeEmail("john+@gmail.com")).toBe("john@gmail.com");
  });

  it("handles multiple + signs (only first matters)", () => {
    expect(normalizeEmail("john+a+b@gmail.com")).toBe("john@gmail.com");
  });

  it("throws on invalid format (no @)", () => {
    expect(() => normalizeEmail("notanemail")).toThrow("Invalid email format");
  });
});

describe("isValidEmail", () => {
  it("accepts valid emails", () => {
    expect(isValidEmail("user@example.com")).toBe(true);
    expect(isValidEmail("user.name+tag@domain.co")).toBe(true);
  });

  it("rejects emails without @", () => {
    expect(isValidEmail("userexample.com")).toBe(false);
  });

  it("rejects emails without domain", () => {
    expect(isValidEmail("user@")).toBe(false);
  });

  it("rejects emails without local part", () => {
    expect(isValidEmail("@example.com")).toBe(false);
  });

  it("rejects emails with spaces", () => {
    expect(isValidEmail("user @example.com")).toBe(false);
  });

  it("rejects empty string", () => {
    expect(isValidEmail("")).toBe(false);
  });
});
