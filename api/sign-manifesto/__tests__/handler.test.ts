import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock AWS SDK modules before importing handler
const mockDdbSend = vi.fn();
const mockSesSend = vi.fn();

vi.mock("@aws-sdk/client-dynamodb", () => ({
  DynamoDBClient: vi.fn(() => ({})),
  ConditionalCheckFailedException: class ConditionalCheckFailedException extends Error {
    name = "ConditionalCheckFailedException";
  },
}));

vi.mock("@aws-sdk/lib-dynamodb", () => ({
  DynamoDBDocumentClient: {
    from: vi.fn(() => ({ send: mockDdbSend })),
  },
  PutCommand: vi.fn((input: unknown) => ({ _type: "Put", input })),
  UpdateCommand: vi.fn((input: unknown) => ({ _type: "Update", input })),
  GetCommand: vi.fn((input: unknown) => ({ _type: "Get", input })),
}));

vi.mock("@aws-sdk/client-ses", () => ({
  SESClient: vi.fn(() => ({ send: mockSesSend })),
  SendEmailCommand: vi.fn((input: unknown) => input),
}));

// Must import after mocks are set up
const { handler } = await import("../handler");

function makeEvent(overrides: Record<string, unknown> = {}) {
  return {
    rawPath: "/sign",
    body: JSON.stringify({ email: "test@example.com" }),
    requestContext: {
      http: {
        method: "POST",
        sourceIp: "127.0.0.1",
      },
    },
    ...overrides,
  };
}

describe("POST /sign", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.TABLE_NAME = "test-table";
  });

  it("returns success with count for valid email", async () => {
    mockDdbSend
      .mockResolvedValueOnce({}) // PutCommand succeeds
      .mockResolvedValueOnce({ Attributes: { signature_count: 42 } }); // UpdateCommand
    mockSesSend.mockResolvedValueOnce({});

    const result = await handler(makeEvent());
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(200);
    expect(body.success).toBe(true);
    expect(body.count).toBe(42);
    expect(body.message).toContain("Welcome to the Coalition");
  });

  it("returns friendly message for duplicate email", async () => {
    const { ConditionalCheckFailedException } = await import(
      "@aws-sdk/client-dynamodb"
    );
    mockDdbSend
      .mockRejectedValueOnce(new ConditionalCheckFailedException({ message: "exists", $metadata: {} }))
      .mockResolvedValueOnce({ Item: { signature_count: 100 } }); // GetCommand for count

    const result = await handler(makeEvent());
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(200);
    expect(body.duplicate).toBe(true);
    expect(body.count).toBe(100);
    expect(body.message).toContain("already signed");
  });

  it("returns 400 for invalid email", async () => {
    const result = await handler(
      makeEvent({ body: JSON.stringify({ email: "not-an-email" }) }),
    );
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(400);
    expect(body.error).toContain("valid email");
  });

  it("returns 400 for missing body", async () => {
    const result = await handler(makeEvent({ body: "" }));
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(400);
  });

  it("returns 400 for missing email field", async () => {
    const result = await handler(makeEvent({ body: JSON.stringify({}) }));
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(400);
    expect(body.error).toContain("valid email");
  });
});

describe("GET /count", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.TABLE_NAME = "test-table";
  });

  it("returns count from DynamoDB", async () => {
    mockDdbSend.mockResolvedValueOnce({
      Item: { signature_count: 256 },
    });

    const result = await handler(
      makeEvent({
        rawPath: "/count",
        requestContext: { http: { method: "GET", sourceIp: "127.0.0.1" } },
      }),
    );
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(200);
    expect(body.count).toBe(256);
  });

  it("returns 0 when counter doesn't exist", async () => {
    mockDdbSend.mockResolvedValueOnce({ Item: undefined });

    const result = await handler(
      makeEvent({
        rawPath: "/count",
        requestContext: { http: { method: "GET", sourceIp: "127.0.0.1" } },
      }),
    );
    const body = JSON.parse(result.body as string);

    expect(result.statusCode).toBe(200);
    expect(body.count).toBe(0);
  });
});

describe("Unknown route", () => {
  it("returns 404 for unknown path", async () => {
    const result = await handler(
      makeEvent({
        rawPath: "/unknown",
        requestContext: { http: { method: "GET", sourceIp: "127.0.0.1" } },
      }),
    );

    expect(result.statusCode).toBe(404);
  });
});
