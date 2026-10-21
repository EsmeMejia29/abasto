const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_PROJECT_ID = "abasto-sv";
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const FIREBASE_PRIVATE_KEY = (Deno.env.get("FIREBASE_PRIVATE_KEY") || "").replace(/\\n/g, "\n");

function base64UrlEncode(data: Uint8Array | string): string {
  const binary = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let str = "";
  for (let i = 0; i < binary.length; i++) {
    str += String.fromCharCode(binary[i]);
  }
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBinary(pem: string): Uint8Array {
  const cleanPem = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(cleanPem);
  const binary = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) {
    binary[i] = raw.charCodeAt(i);
  }
  return binary;
}

async function getGoogleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaimSet = base64UrlEncode(JSON.stringify(claimSet));
  const signatureInput = `${encodedHeader}.${encodedClaimSet}`;

  const binaryKey = pemToBinary(FIREBASE_PRIVATE_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  );

  const jwt = `${signatureInput}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenResponse.json();
  if (!tokenResponse.ok) {
    throw new Error(`Error obteniendo Google Access Token: ${JSON.stringify(tokenData)}`);
  }

  return tokenData.access_token;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const order = payload.record;
    const oldOrder = payload.old_record;

    // Solo notificar si el estado actual es confirmado
    const currentStatus = (order?.status || "").toLowerCase();
    if (currentStatus !== "confirmado") {
      return new Response("No requiere notificación: pedido no confirmado", { status: 200 });
    }

    // Evitar notificaciones duplicadas si ya estaba confirmado previamente
    const previousStatus = (oldOrder?.status || "").toLowerCase();
    if (previousStatus === "confirmado") {
      return new Response("No requiere notificación: el pedido ya estaba confirmado", { status: 200 });
    }

    const supplierId = order.supplier_id;
    if (!supplierId) {
      return new Response("Sin supplier_id", { status: 400 });
    }

    // Buscar token FCM del distribuidor
    const profileRes = await fetch(
      `${SUPABASE_URL}/rest/v1/profiles?id=eq.${supplierId}&select=fcm_token,business_name`,
      {
        headers: {
          apikey: SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );

    const profiles = await profileRes.json();
    const supplierProfile = profiles && profiles.length > 0 ? profiles[0] : null;

    if (!supplierProfile?.fcm_token) {
      return new Response("El distribuidor no tiene fcm_token registrado", { status: 200 });
    }

    // Obtener token OAuth2 y enviar push notification a Firebase
    const accessToken = await getGoogleAccessToken();

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`;
    const messagePayload = {
      message: {
        token: supplierProfile.fcm_token,
        notification: {
          title: `¡Nuevo Pedido Confirmado! (${order.code || 'ORD'})`,
          body: `Tienes una nueva orden confirmada por $${Number(order.total_amount).toFixed(2)}.`,
        },
        data: {
          order_id: String(order.id),
        },
      },
    };

    const pushRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(messagePayload),
    });

    const pushResult = await pushRes.json();
    return new Response(JSON.stringify(pushResult), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});