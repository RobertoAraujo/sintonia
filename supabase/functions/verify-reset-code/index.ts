import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { email, code, newPassword } = await req.json();

    if (!email || !code || !newPassword) {
      return new Response(
        JSON.stringify({ error: "Dados incompletos." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (newPassword.length < 6) {
      return new Response(
        JSON.stringify({ error: "A nova senha deve ter no mínimo 6 caracteres." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Find valid, unused, non-expired code
    const { data: resetRecord, error: fetchError } = await supabaseAdmin
      .from("password_reset_codes")
      .select("*")
      .eq("email", email.toLowerCase())
      .eq("code", code.trim())
      .eq("used", false)
      .gte("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (fetchError) throw fetchError;

    if (!resetRecord) {
      return new Response(
        JSON.stringify({ error: "Código inválido ou expirado. Solicite um novo código." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Find the user by email
    const { data: usersData, error: userListError } = await supabaseAdmin.auth.admin.listUsers();
    if (userListError) throw userListError;

    const user = usersData.users.find(
      (u) => u.email?.toLowerCase() === email.toLowerCase()
    );

    if (!user) {
      return new Response(
        JSON.stringify({ error: "Usuário não encontrado." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update the user's password
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      user.id,
      { password: newPassword }
    );

    if (updateError) throw updateError;

    // Mark the code as used
    await supabaseAdmin
      .from("password_reset_codes")
      .update({ used: true })
      .eq("id", resetRecord.id);

    return new Response(
      JSON.stringify({ success: true, message: "Senha redefinida com sucesso!" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("verify-reset-code error:", error);
    return new Response(
      JSON.stringify({ error: "Erro interno. Tente novamente." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
