import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  // Responder al preflight CORS del navegador
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { orderId, orderCode, amount, customerEmail } = await req.json();

    if (!orderCode || !amount) {
      throw new Error("Faltan datos requeridos: orderCode o amount");
    }

    const WOMPI_APP_ID = Deno.env.get("WOMPI_APP_ID");
    const WOMPI_API_SECRET = Deno.env.get("WOMPI_API_SECRET");

    if (!WOMPI_APP_ID || !WOMPI_API_SECRET) {
      throw new Error("Faltan credenciales WOMPI_APP_ID o WOMPI_API_SECRET en Supabase Secrets");
    }

    // 1. Obtener Token OAuth de Wompi El Salvador
    const tokenRes = await fetch("https://id.wompi.sv/connect/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: WOMPI_APP_ID,
        client_secret: WOMPI_API_SECRET,
        audience: "wompi_api",
      }),
    });

    const tokenData = await tokenRes.json();
    if (!tokenRes.ok || !tokenData.access_token) {
      throw new Error(`Error autenticando con Wompi: ${JSON.stringify(tokenData)}`);
    }

    // 2. Crear Enlace de Pago en Wompi El Salvador apuntando a abasto-sv.vercel.app
    const enlaceRes = await fetch("https://api.wompi.sv/EnlacePago", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${tokenData.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        identificadorEnlaceComercio: orderCode,
        monto: Number(amount),
        nombreProducto: `Pedido Abasto ${orderCode}`,
        formaPago: {
          permitirTarjetaCreditoDebido: true,
          permitirPagoConPuntoAgricola: true,
          permitirPagoEnCuotasAgricola: false,
          permitirPagoEnBitcoin: false,
          permitirPagoConTransferencia: false,
        },
        infoProducto: {
          descripcionProducto: `Abastecimiento B2B de insumos • Orden ${orderCode}`,
          urlImagenProducto: "https://abasto-sv.vercel.app/icons/Icon-512.png",
        },
        configuracion: {
          urlRedirect: `https://abasto-sv.vercel.app/?identificadorEnlaceComercio=${encodeURIComponent(orderCode)}`,
          esMontoEditable: false,
          esCantidadEditable: false,
          cantidadPorDefecto: 1,
          duracionInterfazIntentoMinutos: 30,
          urlWebhook: "https://huyxrfowjiqllvzedzgz.supabase.co/functions/v1/wompi-webhook",
          notificarTransaccionCliente: true,
        },
        datosAdicionales: {
          orderId: String(orderId ?? ""),
          customerEmail: customerEmail ?? "restaurante@abasto.sv",
        },
      }),
    });

    const enlaceData = await enlaceRes.json();
    const paymentUrl =
      enlaceData.urlEnlace ||
      enlaceData.url ||
      enlaceData.urlQrCodeEnlace;

    if (!enlaceRes.ok || !paymentUrl) {
      throw new Error(`Error creando enlace en Wompi: ${JSON.stringify(enlaceData)}`);
    }

    return new Response(
      JSON.stringify({
        url: paymentUrl,
        idEnlace: enlaceData.idEnlace,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("Error en create-wompi-payment:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});