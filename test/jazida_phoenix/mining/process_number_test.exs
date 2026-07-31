defmodule JazidaPhoenix.Mining.ProcessNumberTest do
  use ExUnit.Case, async: true

  alias JazidaPhoenix.Mining.{ProcessNumber, Status}

  test "strictly normalizes accepted SOPLE identifiers" do
    assert {:ok, %{process_number: "000100/1966", number: 100, year: 1966}} =
             ProcessNumber.normalize(" 100/1966 ")

    assert {:ok, %{process_number: "844001/2022"}} = ProcessNumber.normalize("844001/2022")
  end

  test "rejects punctuation and injection payloads rather than stripping them" do
    assert :error = ProcessNumber.normalize("844.001/2022")
    assert :error = ProcessNumber.normalize("844001/2022' OR 1=1--")
    assert :error = ProcessNumber.normalize("0/2026")
    assert :error = ProcessNumber.normalize("000001/1800")
    assert :error = ProcessNumber.normalize(nil)
  end

  test "allows only the documented SIGMINE thousands separator" do
    assert {:ok, %{process_number: "844001/2022"}} =
             ProcessNumber.normalize_sigmine("844.001/2022")

    assert :error = ProcessNumber.normalize_sigmine("844-001-2022")
  end

  test "maps known labels and warns on unknown labels" do
    assert {:ok, "eligible"} = Status.stock("Apta para Disponibilidade")
    assert {:ok, "awarded"} = Status.result("Arrematada")
    assert {:warning, "unknown"} = Status.result("Novo status oficial")
    assert {:ok, "eligible"} = Status.availability("Apta para Disponibilidade", "")
  end
end
