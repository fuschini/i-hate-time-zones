/**
 * Integration tests for the sign-manifesto Lambda handler.
 *
 * These tests require a real DynamoDB table. Set the TABLE_NAME env var
 * to point at a test table (e.g. the dev table or DynamoDB Local).
 *
 * Run: TABLE_NAME=ihatetimezones-dev-signatures npm test -- __tests__/integration.test.ts
 */
import { describe, it, expect, beforeAll } from "vitest";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, DeleteCommand } from "@aws-sdk/lib-dynamodb";

const TABLE_NAME = process.env.TABLE_NAME;

// Skip these tests if no TABLE_NAME is provided
const describeIntegration = TABLE_NAME ? describe : describe.skip;

describeIntegration("Integration: sign-manifesto", () => {
  let handler: typeof import("../handler").handler;
  let ddb: DynamoDBDocumentClient;

  beforeAll(async () => {
    const mod = await import("../handler");
    handler = mod.handler;

    const client = new DynamoDBClient({});
    ddb = DynamoDBDocumentClient.from(client);
  });

  const testEmail = `integration-test-${Date.now()}@example.com`;

  async function cleanup() {
    const { normalizeEmail } = await import("../normalize");
    const normalized = normalizeEmail(testEmail);
    try {
      await ddb.send(
        new DeleteCommand({
          TableName: TABLE_NAME!,
          Key: { pk: `EMAIL#${normalized}` },
        }),
      );
    } catch {
      // ignore
    }
  }

  function makeEvent(overrides: Record<string, unknown> = {}) {
    return {
      rawPath: "/sign",
      body: JSON.stringify({ email: testEmail }),
      requestContext: {
        http: { method: "POST", sourceIp: "127.0.0.1" },
      },
      ...overrides,
    } as any;
  }

  it("sign → count increments → sign same email → count unchanged", async () => {
    await cleanup();

    // Get initial count
    const countBefore = await handler({
      rawPath: "/count",
      requestContext: { http: { method: "GET", sourceIp: "127.0.0.1" } },
    } as any);
    const initialCount = JSON.parse(countBefore.body as string).count;

    // Sign
    const signResult = await handler(makeEvent());
    const signBody = JSON.parse(signResult.body as string);
    expect(signBody.success).toBe(true);
    expect(signBody.count).toBe(initialCount + 1);

    // Count should have incremented
    const countAfter = await handler({
      rawPath: "/count",
      requestContext: { http: { method: "GET", sourceIp: "127.0.0.1" } },
    } as any);
    expect(JSON.parse(countAfter.body as string).count).toBe(initialCount + 1);

    // Sign same email again — should be duplicate
    const dupResult = await handler(makeEvent());
    const dupBody = JSON.parse(dupResult.body as string);
    expect(dupBody.duplicate).toBe(true);
    expect(dupBody.count).toBe(initialCount + 1); // unchanged

    await cleanup();
  });

  it("sign with + variant is treated as duplicate", async () => {
    await cleanup();

    // Sign with base email
    await handler(makeEvent());

    // Sign with + variant
    const plusEmail = testEmail.replace("@", "+variant@");
    const dupResult = await handler(
      makeEvent({ body: JSON.stringify({ email: plusEmail }) }),
    );
    const dupBody = JSON.parse(dupResult.body as string);
    expect(dupBody.duplicate).toBe(true);

    await cleanup();
  });

  it("sign with . variant is treated as duplicate", async () => {
    await cleanup();

    // Sign with base email
    await handler(makeEvent());

    // Sign with dot variant — add a dot after first char
    const [local, domain] = testEmail.split("@");
    const dotEmail = `${local[0]}.${local.slice(1)}@${domain}`;
    const dupResult = await handler(
      makeEvent({ body: JSON.stringify({ email: dotEmail }) }),
    );
    const dupBody = JSON.parse(dupResult.body as string);
    expect(dupBody.duplicate).toBe(true);

    await cleanup();
  });
});
