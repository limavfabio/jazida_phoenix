defmodule JazidaPhoenix.Mining.SopleParserTest do
  use ExUnit.Case, async: true

  alias JazidaPhoenix.Mining.SopleParser

  @fixtures Path.expand("../../support/fixtures/anm", __DIR__)

  test "parses BOM, accents, quoted semicolons, booleans, and Brazilian decimals" do
    result = SopleParser.stock_rows(Path.join(@fixtures, "sople_stock.csv"))

    assert length(result.rows) == 3
    assert [%{kind: "invalid_process_number"}] = result.warnings

    quoted = Enum.find(result.rows, &(&1.process.process_number == "811171/2016"))
    assert quoted.process.state_code == "RS"
    assert quoted.process.area_ha == Decimal.new("48.38")
    assert quoted.process.substances == ["AREIA", "ARGILA"]
    assert quoted.availability.display_category == "free"
    refute Map.has_key?(quoted, :winner)
  end

  test "does not retain winner identity fields from round results" do
    result = SopleParser.round_rows(Path.join(@fixtures, "sople_round_results.csv"))

    assert length(result.rows) == 3
    assert [%{kind: "invalid_round_row"}] = result.warnings
    awarded = Enum.find(result.rows, &(&1.process.process_number == "800277/2011"))
    assert awarded.round_area.winning_bid_brl == Decimal.new("1237.44")
    assert awarded.round_area.display_category == "awarded"
    refute Map.has_key?(awarded.round_area, :winner_name)
  end
end
