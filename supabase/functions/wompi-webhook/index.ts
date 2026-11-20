import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    console.log("Webhook Wompi recibido:", JSON.stringify(payload));

    const resultado = (payload.ResultadoTransaccion || payload.resultadoTransaccion || "").toString();
    const esAprobada =
      resultado.toLowerCase().includes("exitosa") ||
      resultado.toLowerCase().includes("aprobada") ||
      payload.EsAprobada === true;

    const orderCode =
      payload.EnlacePago?.IdentificadorEnlaceComercio ||
      payload.IdentificadorEnlaceComercio ||
      payload.identificadorEnlaceComercio;

    const monto = payload.Monto || payload.monto || 0;
    const idTransaccion = payload.IdTransaccion || payload.idTransaccion || "N/A";

    if (!esAprobada || !orderCode) {
      return new Response(
        JSON.stringify({ received: true, updated: false, reason: "No aprobada o sin orderCode" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    const { data: order, error: fetchError } = await supabase
      .from("orders")
      .select("id, status, status_history, delivery_pin")
      .eq("code", orderCode)
      .single();

    if (fetchError || !order) {
      throw new Error(`Orden no encontrada para el código: ${orderCode}`);
    }

    if (order.status === "confirmado") {
      return new Response(JSON.stringify({ received: true, alreadyConfirmed: true }), { status: 200 });
    }

    const existingPin = (order.delivery_pin ?? "").toString().trim();
    const generatedPin =
      existingPin.length === 4
        ? existingPin
        : Math.floor(1000 + Math.random() * 9000).toString();

    const currentHistory = Array.isArray(order.status_history) ? order.status_history : [];
    const newHistory = [
      ...currentHistory,
      {
        status: "confirmado",
        changed_at: new Date().toISOString(),
        note: `Pago verificado automáticamente por Wompi (Ref: ${idTransaccion} • $${Number(monto).toFixed(2)})`,
      },
    ];

    const { error: updateError } = await supabase
      .from("orders")
      .update({
        status: "confirmado",
        payment_reference: idTransaccion,
        status_history: newHistory,
        delivery_pin: generatedPin,
      })
      .eq("id", order.id);

    if (updateError) throw updateError;

    return new Response(JSON.stringify({ received: true, updated: true, orderCode }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error en wompi-webhook:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
});