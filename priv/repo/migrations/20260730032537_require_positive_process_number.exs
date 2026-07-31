defmodule JazidaPhoenix.Repo.Migrations.RequirePositiveProcessNumber do
  use Ecto.Migration

  def up do
    execute("DELETE FROM mining_processes WHERE number = 0")
    drop constraint(:mining_processes, :mining_processes_number_range)

    create constraint(:mining_processes, :mining_processes_number_range,
             check: "number BETWEEN 1 AND 999999"
           )
  end

  def down do
    drop constraint(:mining_processes, :mining_processes_number_range)

    create constraint(:mining_processes, :mining_processes_number_range,
             check: "number BETWEEN 0 AND 999999"
           )
  end
end
