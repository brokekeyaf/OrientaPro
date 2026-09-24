-- =====================================================================
-- OrientaPro · 005_storage.sql
-- Bucket privado para os currículos em PDF (RN04, RN10, RNF10).
-- Caminho de cada arquivo: {id_usuario}/{uuid}.pdf
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('curriculos', 'curriculos', false, 5242880, array['application/pdf'])   -- 5 MB, só PDF
on conflict (id) do update
  set public = false, file_size_limit = 5242880, allowed_mime_types = array['application/pdf'];

-- O estudante envia, lê e apaga apenas arquivos da própria pasta.
create policy "curriculos: dono envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'curriculos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "curriculos: dono le" on storage.objects for select to authenticated
  using (bucket_id = 'curriculos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "curriculos: dono apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'curriculos' and (storage.foldername(name))[1] = auth.uid()::text);

-- RN10: a empresa lê o PDF somente se ele foi enviado em candidatura para uma vaga dela.
create policy "curriculos: empresa le candidatura" on storage.objects for select to authenticated
  using (bucket_id = 'curriculos' and exists (
    select 1 from public.curriculos c
      join public.candidaturas ca on ca.id_curriculo = c.id_curriculo
      join public.vagas v         on v.id_vaga = ca.id_vaga
      join public.empresas e      on e.id_empresa = v.id_empresa
     where c.caminho_arquivo = storage.objects.name
       and e.id_usuario_responsavel = auth.uid()));
