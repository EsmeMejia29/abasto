import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create } from "https://deno.land/x/djwt@v2.8/mod.ts";

// Configuración de Supabase
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Reemplaza o configura como variables de entorno con los datos de tu archivo .json de Firebase:
const FIREBASE_PROJECT_ID = "abasto-sv";
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const FIREBASE_PRIVATE_KEY = Deno.env.get("FIREBASE_PRIVATE_KEY")!.replace(/\\n/g, "\n");

// Función para obtener Token de acceso OAuth2 para la API de Firebase v1
async function getAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: FIREBASE_CLIENT_EMAIL,
      sub: FIREBASE_CLIENT_EMAIL,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    },
    await crypto.subtle.importKey(
      "pkcs8",
      Uint8Array.from(atob(FIREBASE_PRIVATE_KEY.replace(/-----[^\n]+-----|\n/g, "")), (c) => c.charCodeAt(0)),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    )
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  return data.access_token;
}

serve(async (req) => {
  try {
    const payload = await req.json();
    const order = payload.record; // Orden recién insertada o modificada

    // Solo notificar si la orden está confirmada
    if (order.status !== "confirmado") {
      return new Response("No requiere notificación", { status: 200 });
    }

    const supplierId = order.supplier_id;
    if (!supplierId) {
      return new Response("Sin supplier_id", { status: 400 });
    }

    // 1. Buscar el fcm_token del Distribuidor en profiles
    const { data: profile, error } = await supabase
      .from("profiles")
      .select("fcm_token, business_name")
      .eq("id", supplierId)
      .single();

    if (error || !profile?.fcm_token) {
      return new Response("El distribuidor no tiene fcm_token registrado", { status: 200 });
    }

    // 2. Obtener Token de Google
    const accessToken = await getAccessToken();

    // 3. Enviar Notificación a Firebase Cloud Messaging v1
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`;
    const messagePayload = {
      message: {
        token: profile.fcm_token,
        notification: {
          title: `¡Nuevo Pedido Confirmado! (${order.code || 'ORD'})`,
          body: `Tienes una nueva orden por $${Number(order.total_amount).toFixed(2)} lista para preparación.`,
        },
        data: {
          order_id: String(order.id),
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
    };

    const pushRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(messagePayload),
    });

    const pushResult = await pushRes.json();
    return new Response(JSON.stringify(pushResult), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(String(err), { status: 500 });
  }
});