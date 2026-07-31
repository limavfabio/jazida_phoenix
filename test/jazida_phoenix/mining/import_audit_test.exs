defmodule JazidaPhoenix.Mining.ImportAuditTest do
  use JazidaPhoenix.DataCase, async: true

  alias JazidaPhoenix.Mining.{ImportAudit, SourceImport}

  test "records a bounded operator-visible download failure without advancing freshness" do
    assert {:error, failed} =
             ImportAudit.record_download_failure(
               "sople_stock",
               "https://anm.test/source.csv",
               {:http_status, 503}
             )

    assert failed.status == "failed"
    assert failed.error_summary == "{:http_status, 503}"
    assert Repo.aggregate(SourceImport, :count) == 1
    assert is_nil(JazidaPhoenix.Mining.latest_successful_import("sople_stock"))
  end
end
