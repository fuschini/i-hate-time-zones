import { createHash } from "node:crypto";
import {
  DynamoDBClient,
  ConditionalCheckFailedException,
} from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  UpdateCommand,
  GetCommand,
} from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { normalizeEmail, isValidEmail } from "./normalize";
import { sendConfirmationEmail } from "./email";

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.TABLE_NAME!;

export async function handler(
  event: APIGatewayProxyEventV2,
): Promise<APIGatewayProxyResultV2> {
  const method = event.requestContext.http.method;
  const path = event.rawPath;

  try {
    if (method === "POST" && path === "/sign") {
      return await handleSign(event);
    }
    if (method === "GET" && path === "/count") {
      return await handleCount();
    }
    return response(404, { error: "Not found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return response(500, {
      error: "Something went wrong on our end. Please try again later.",
    });
  }
}

async function handleSign(
  event: APIGatewayProxyEventV2,
): Promise<APIGatewayProxyResultV2> {
  let body: { email?: string };
  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return response(400, { error: "Invalid request body." });
  }

  const email = body.email?.trim();
  if (!email || !isValidEmail(email)) {
    return response(400, {
      error: "Please provide a valid email address.",
    });
  }

  const normalized = normalizeEmail(email);
  const pk = `EMAIL#${normalized}`;
  const ipHash = createHash("sha256")
    .update(event.requestContext.http.sourceIp || "unknown")
    .digest("hex");

  // Try to insert the signature (conditional on not existing)
  try {
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          pk,
          email,
          normalized_email: normalized,
          signed_at: new Date().toISOString(),
          ip_hash: ipHash,
        },
        ConditionExpression: "attribute_not_exists(pk)",
      }),
    );
  } catch (err) {
    if (err instanceof ConditionalCheckFailedException) {
      // Duplicate — return friendly message with current count
      const count = await getCount();
      return response(200, {
        success: true,
        duplicate: true,
        count,
        message:
          "You've already joined. Your opposition to time zones has been noted.",
      });
    }
    throw err;
  }

  // Atomically increment the counter
  const countResult = await ddb.send(
    new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { pk: "COUNTER#total" },
      UpdateExpression: "ADD signature_count :val",
      ExpressionAttributeValues: { ":val": 1 },
      ReturnValues: "ALL_NEW",
    }),
  );

  const count = (countResult.Attributes?.signature_count as number) || 0;

  // Send confirmation email
  try {
    await sendConfirmationEmail(email, count);
  } catch (err) {
    console.error("Failed to send confirmation email:", err);
  }

  return response(200, {
    success: true,
    count,
    message: "Welcome to the Coalition. Your support has been recorded.",
  });
}

async function handleCount(): Promise<APIGatewayProxyResultV2> {
  const count = await getCount();
  return response(200, { count });
}

async function getCount(): Promise<number> {
  const result = await ddb.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: { pk: "COUNTER#total" },
    }),
  );
  return (result.Item?.signature_count as number) || 0;
}

function response(
  statusCode: number,
  body: Record<string, unknown>,
): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
