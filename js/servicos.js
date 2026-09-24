/*
 * OrientaPro · camada de serviços (Documento, seção 4.1)
 * Toda comunicação com o Supabase passa por aqui. As telas (index.html)
 * só chamam window.OP.auth, window.OP.teste e window.OP.curriculo.
 *
 * Se js/supabase-config.js estiver vazio, OP.ativo = false e o site
 * continua em modo demonstração (localStorage).
 */
window.OP = (function () {
  'use strict';

  const cfg = window.OP_CONFIG || {};
  const ativo = !!(cfg.url && cfg.anonKey && window.supabase && window.supabase.createClient);
  const sb = ativo
    ? window.supabase.createClient(cfg.url, cfg.anonKey, { auth: { flowType: 'pkce', persistSession: true, detectSessionInUrl: true } })
    : null;

  // Endereço do site sem hash nem query (usado nos links de confirmação e de nova senha)
  const siteUrl = () => location.origin + location.pathname;

  /* ---------- mensagens de erro em português ---------- */
  function traduzir(err) {
    const m = String((err && (err.message || err.error_description)) || err || '');
    const code = err && err.code;
    if (/Invalid login credentials/i.test(m)) return 'E-mail ou senha incorretos.';
    if (/Email not confirmed/i.test(m)) return 'Confirme seu e-mail antes de entrar. Procure a mensagem do OrientaPro na sua caixa de entrada.';
    if (/User already registered/i.test(m)) return 'Não foi possível concluir o cadastro. Se você já tem conta, faça login ou recupere a senha.';
    if (/RN03|14 anos/i.test(m) || /Database error saving new user/i.test(m)) return 'Não foi possível criar a conta. É preciso ter pelo menos 14 anos (RN03).';
    if (/rate limit|too many|429/i.test(m) || code === 'over_email_send_rate_limit') return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente de novo.';
    if (/Password should be|weak_password|password/i.test(m) && /least|weak|character/i.test(m)) return 'Senha fraca: use ao menos 8 caracteres, com letras e números.';
    if (/ck_curriculos_resumo/.test(m)) return 'O resumo é obrigatório para salvar o currículo.';
    if (/ck_experiencias_datas/.test(m)) return 'Em uma experiência, a data de fim é anterior à data de início.';
    if (/ck_formacoes_anos/.test(m)) return 'Em uma formação, o ano de conclusão é anterior ao ano de início.';
    if (/fk_candidaturas_curriculo/.test(m)) return 'Este currículo foi usado em uma candidatura e não pode ser excluído.';
    if (/exceeded the maximum allowed size|Payload too large|413/i.test(m)) return 'O PDF passa de 5 MB (RN04).';
    if (/mime type|invalid_mime_type/i.test(m)) return 'Envie apenas arquivos PDF (RN04).';
    if (/Failed to fetch|NetworkError/i.test(m)) return 'Sem conexão com o servidor. Verifique a internet e tente de novo.';
    return m || 'Algo deu errado. Tente de novo.';
  }
  function falhar(error) { const e = new Error(traduzir(error)); e.original = error; throw e; }

  /* ================= AUTENTICAÇÃO (UC01, UC02, RF03) ================= */
  let perfilCache = null;

  const auth = {
    async cadastrar({ nome, email, senha, nascimento }) {
      const { data, error } = await sb.auth.signUp({
        email, password: senha,
        options: {
          emailRedirectTo: siteUrl(),
          data: { nome_completo: nome, data_nascimento: nascimento, tipo_usuario: 'ESTUDANTE' }
        }
      });
      if (error) falhar(error);
      // Com confirmação de e-mail ligada, a sessão só existe depois do clique no link.
      return { precisaConfirmar: !data.session };
    },

    async entrar(email, senha) {
      const { data, error } = await sb.auth.signInWithPassword({ email, password: senha });
      if (error) falhar(error);
      perfilCache = null;
      const p = await auth.perfil();
      if (p && p.ativo === false) {           // UC02 · FE02: usuário bloqueado
        await sb.auth.signOut();
        throw new Error('Sua conta está bloqueada. Motivo: ' + (p.motivo_bloqueio || 'não informado') + '.');
      }
      return data.user;
    },

    async sair() { perfilCache = null; await sb.auth.signOut(); },

    async recuperarSenha(email) {
      const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: siteUrl() });
      if (error) falhar(error);
    },

    async definirNovaSenha(senha) {
      const { error } = await sb.auth.updateUser({ password: senha });
      if (error) falhar(error);
    },

    async usuario() {
      const { data } = await sb.auth.getSession();
      return data.session ? data.session.user : null;
    },

    async perfil() {
      if (perfilCache) return perfilCache;
      const u = await auth.usuario();
      if (!u) return null;
      const { data, error } = await sb.from('usuarios')
        .select('id_usuario, nome_completo, email, telefone, tipo_usuario, ativo, motivo_bloqueio')
        .eq('id_usuario', u.id).maybeSingle();
      if (error) falhar(error);
      perfilCache = data;
      return data;
    },

    // cb(evento, sessão). O setTimeout evita chamar o Supabase dentro do próprio callback.
    aoMudar(cb) {
      sb.auth.onAuthStateChange((evento, sessao) => {
        if (evento === 'SIGNED_OUT' || evento === 'SIGNED_IN' || evento === 'USER_UPDATED') perfilCache = null;
        setTimeout(() => cb(evento, sessao), 0);
      });
    }
  };

  /* ================= TESTE VOCACIONAL (UC05) ================= */
  let areasCache = null;
  async function areas() {
    if (areasCache) return areasCache;
    const { data, error } = await sb.from('areas_profissionais').select('id_area, nome').order('id_area');
    if (error) falhar(error);
    areasCache = data;
    return data;
  }

  const teste = {
    // Devolve [{ id_pergunta, enunciado, alternativas:[{ id_alternativa, texto, area }] }]
    async carregarPerguntas() {
      const [ar, pq, al] = await Promise.all([
        areas(),
        sb.from('perguntas_teste').select('id_pergunta, ordem, enunciado').order('ordem'),
        sb.from('alternativas').select('id_alternativa, id_pergunta, id_area, texto').order('id_alternativa')
      ]);
      if (pq.error) falhar(pq.error);
      if (al.error) falhar(al.error);
      const nomeArea = Object.fromEntries(ar.map(a => [a.id_area, a.nome]));
      return pq.data.map(p => ({
        id_pergunta: p.id_pergunta,
        enunciado: p.enunciado,
        alternativas: al.data.filter(a => a.id_pergunta === p.id_pergunta)
          .map(a => ({ id_alternativa: a.id_alternativa, texto: a.texto, area: nomeArea[a.id_area] }))
      }));
    },

    async registrar(idsAlternativas) {
      const { data, error } = await sb.rpc('registrar_teste', { p_alternativas: idsAlternativas });
      if (error) falhar(error);
      return data;   // { id_teste, id_area, area, pontos:[{area, pontos}] }
    },

    async historico(limite = 5) {
      const ar = await areas();
      const nomeArea = Object.fromEntries(ar.map(a => [a.id_area, a.nome]));
      const { data, error } = await sb.from('testes_vocacionais')
        .select('id_teste, concluido_em, id_area_recomendada')
        .eq('status', 'CONCLUIDO').order('concluido_em', { ascending: false }).limit(limite);
      if (error) falhar(error);
      return data.map(t => ({ ...t, area: nomeArea[t.id_area_recomendada] }));
    }
  };

  /* ================= CURRÍCULO (UC03, UC04) ================= */
  const LIMITE_PDF = 5 * 1024 * 1024;   // RN04

  const curriculo = {
    async listar() {
      const { data, error } = await sb.from('curriculos')
        .select('id_curriculo, titulo, origem, caminho_arquivo, atualizado_em')
        .order('atualizado_em', { ascending: false });
      if (error) falhar(error);
      return data;
    },

    async carregar(id) {
      const { data, error } = await sb.from('curriculos')
        .select('*, formacoes(*), experiencias(*), curriculo_habilidades(habilidades(nome))')
        .eq('id_curriculo', id).single();
      if (error) falhar(error);
      data.habilidades = (data.curriculo_habilidades || []).map(x => x.habilidades && x.habilidades.nome).filter(Boolean);
      data.formacoes.sort((a, b) => a.id_formacao - b.id_formacao);
      data.experiencias.sort((a, b) => a.id_experiencia - b.id_experiencia);
      return data;
    },

    // dados = { id_curriculo?, titulo, resumo, telefone, cidade, idiomas, formacoes[], experiencias[], habilidades[] }
    async salvar(dados) {
      const { data, error } = await sb.rpc('salvar_curriculo', { p: dados });
      if (error) falhar(error);
      return data;   // id_curriculo
    },

    async enviarPdf(arquivo, titulo) {
      if (!arquivo) throw new Error('Escolha um arquivo PDF.');
      const ehPdf = arquivo.type === 'application/pdf' || /\.pdf$/i.test(arquivo.name);
      if (!ehPdf) throw new Error('Envie apenas arquivos PDF (RN04).');
      if (arquivo.size > LIMITE_PDF) throw new Error('O PDF passa de 5 MB (RN04).');
      const u = await auth.usuario();
      if (!u) throw new Error('Faça login para enviar o currículo.');

      const caminho = u.id + '/' + crypto.randomUUID() + '.pdf';
      const up = await sb.storage.from('curriculos').upload(caminho, arquivo, { contentType: 'application/pdf', upsert: false });
      if (up.error) falhar(up.error);

      const { error } = await sb.from('curriculos').insert({
        id_usuario: u.id, titulo: titulo || arquivo.name.replace(/\.pdf$/i, ''), origem: 'UPLOAD', caminho_arquivo: caminho
      });
      if (error) {                                   // UC04 · FE02: não deixa arquivo órfão
        await sb.storage.from('curriculos').remove([caminho]);
        falhar(error);
      }
    },

    async urlPdf(caminho) {
      const { data, error } = await sb.storage.from('curriculos').createSignedUrl(caminho, 120);  // link vale 2 minutos
      if (error) falhar(error);
      return data.signedUrl;
    },

    async excluir(item) {
      const { error } = await sb.from('curriculos').delete().eq('id_curriculo', item.id_curriculo);
      if (error) falhar(error);
      if (item.caminho_arquivo) await sb.storage.from('curriculos').remove([item.caminho_arquivo]);
    }
  };

  return { ativo, sb, auth, teste, curriculo, traduzir };
})();
