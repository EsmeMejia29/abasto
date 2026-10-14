import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const APP_ID = Deno.env.get("1b92dec1-cc66-49e2-876a-b6fbb8dd79f2")!;       // 1b92dec1-...
const API_SECRET = Deno.env.get("fb81fc4c-11df-4701-9f26-9f2180d646d6")!; // fb81fc4c-...

serve(async (req) => {
  try {
    const { orderId, amount, customerEmail, orderCode } = await req.json();

    // 1. Solicitar token OAuth 2.0 a Wompi
    const tokenRes = await fetch("https://id.wompi.sv/connect/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: APP_ID,
        client_secret: API_SECRET,
        audience: "wompi_api",
      }),
    });
    const tokenData = await tokenRes.json();
    const accessToken = tokenData.access_token;

    // 2. Crear Enlace de Pago en Wompi
    const linkRes = await fetch("https://api.wompi.sv/EnlacePago", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        identificadorEnlaceComercio: orderCode,
        monto: amount,
        nombreProducto: `Pedido Abasto ${orderCode}`,
        formaPago: {
          permitirTarjetaCreditoDebito: true,
          permitirPagoConPuntoAgricola: false,
        },
        configuracion: {
          urlRedirect: "https://abasto-flame.vercel.app/#/orders",
          esMontoEditable: false,
          esCantidadEditable: false,
        },
      }),
    });

    const linkData = await linkRes.json();

    return new Response(JSON.stringify({ url: linkData.urlEnlace }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});