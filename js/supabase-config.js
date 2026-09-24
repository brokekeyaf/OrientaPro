/*
 * OrientaPro · configuração do Supabase
 *
 * 1. No painel do Supabase: Project Settings > API (ou "Connect").
 * 2. Copie a "Project URL" e a chave "anon public" (ou "publishable") para os campos abaixo.
 *
 * A chave anon é pública: ela pode ficar no site porque TODAS as tabelas têm RLS.
 * NUNCA coloque aqui a chave "service_role" (ou "secret"): ela ignora o RLS.
 *
 * Com os campos vazios, o site funciona em "modo demonstração" (dados só no navegador).
 */
window.OP_CONFIG = {
  url: 'https://dztpkbejvwrzzrfyhzzm.supabase.co',
  anonKey: 'sb_publishable_q1-J05q_9cUnrhApKysU4Q_jKKt7oWg'
};
