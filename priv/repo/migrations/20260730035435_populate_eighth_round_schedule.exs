defmodule JazidaPhoenix.Repo.Migrations.PopulateEighthRoundSchedule do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO rounds
      (number, title, official_process_number, notice_url, source_url, status, timezone, inserted_at, updated_at)
    VALUES
      (8, '8ª Rodada de Disponibilidade de Áreas', '48051.007646/2023-43',
       'https://sople.anm.gov.br/', 'https://sople.anm.gov.br/', 'concluída',
       'America/Sao_Paulo', now(), now())
    ON CONFLICT (number) DO UPDATE SET
      title = EXCLUDED.title,
      official_process_number = EXCLUDED.official_process_number,
      notice_url = EXCLUDED.notice_url,
      source_url = EXCLUDED.source_url,
      status = EXCLUDED.status,
      timezone = EXCLUDED.timezone,
      updated_at = now()
    """)

    execute("""
    INSERT INTO round_events
      (round_id, slug, name, starts_at, ends_at, official_label, source_reference, inserted_at, updated_at)
    SELECT r.id, event.slug, event.name, event.starts_at::timestamp, event.ends_at::timestamp,
           event.official_label, 'Edital nº 01/2024, Tabela 1', now(), now()
    FROM rounds r
    CROSS JOIN (VALUES
      ('public-offer', 'Oferta pública', '2024-05-21 11:00:00', '2024-07-22 19:00:00', 'Período de Oferta Pública no SOPLE'),
      ('preliminary-result', 'Resultado preliminar', '2024-07-22 03:00:00', '2024-07-23 02:59:59', 'Divulgação do Resultado preliminar da fase de Oferta Pública'),
      ('electronic-auction', 'Leilão eletrônico', '2024-07-23 11:00:00', '2024-07-31 19:00:00', 'Período do Leilão Eletrônico'),
      ('administrative-appeals', 'Recursos administrativos', '2024-08-01 11:00:00', '2024-10-09 02:59:59', 'Interposição e análise de recursos administrativos'),
      ('final-result', 'Homologação e adjudicação', '2024-10-14 03:00:00', '2024-10-19 02:59:59', 'Publicação do ato de homologação e adjudicação'),
      ('payment', 'Pagamento', '2024-10-21 03:00:00', '2024-11-02 02:59:59', 'Período para pagamentos integrais'),
      ('title-application', 'Requerimento de título', '2024-10-21 11:00:00', '2024-11-25 19:00:00', 'Período para Requerimentos de Títulos Minerários'),
      ('sanctions', 'Processo sancionador', '2024-11-04 03:00:00', '2027-11-05 02:59:59', 'Processo Sancionador')
    ) AS event(slug, name, starts_at, ends_at, official_label)
    WHERE r.number = 8
    ON CONFLICT (round_id, slug) DO NOTHING
    """)
  end

  def down do
    execute("""
    DELETE FROM round_events
    WHERE round_id = (SELECT id FROM rounds WHERE number = 8)
      AND source_reference = 'Edital nº 01/2024, Tabela 1'
    """)

    execute("""
    UPDATE rounds
    SET official_process_number = NULL, notice_url = NULL, source_url = NULL,
        status = NULL, updated_at = now()
    WHERE number = 8
    """)
  end
end
