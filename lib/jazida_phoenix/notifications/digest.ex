defmodule JazidaPhoenix.Notifications.Digest do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending sent failed)

  schema "digests" do
    field :calendar_date, :date
    field :status, :string
    field :notification_count, :integer, default: 0
    field :sent_at, :utc_datetime
    field :error_summary, :string
    belongs_to :user, JazidaPhoenix.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(digest, attrs) do
    digest
    |> cast(attrs, [:calendar_date, :status, :notification_count, :sent_at, :error_summary])
    |> validate_required([:calendar_date, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:notification_count, greater_than_or_equal_to: 0)
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :calendar_date])
    |> check_constraint(:status, name: :digests_status)
    |> check_constraint(:notification_count, name: :digests_notification_count_non_negative)
  end
end
