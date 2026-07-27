defmodule VNI.Pledges.Notifier do
  @moduledoc """
  The two emails a commitment ever sends: confirm it, and recover the link
  to manage or withdraw it.

  Both are plain text. This is a political mailing list, and a plain
  message from a project that publishes its methodology reads more like
  what it is than a templated HTML campaign would.

  CAN-SPAM basics travel on every send: who it is from, why it arrived,
  and how to leave — the withdrawal link is in the body, not buried behind
  a preference centre.
  """

  import Swoosh.Email

  alias VNI.Mailer

  @doc """
  The envelope these leave under, from config rather than baked in.

  Resend will only send from a domain verified in the account, so this
  has to track whatever domain is verified — and it changes without a
  recompile (`MAIL_FROM`), because a bounced sending domain is not
  something to wait on a deploy for.
  """
  def from, do: Application.fetch_env!(:vni, __MODULE__)[:from]

  @doc "Double opt-in. Nothing counts until this link is clicked."
  def deliver_confirmation(email, seat_label, incumbent, url) do
    deliver(email, "Confirm your commitment in #{seat_label}", """
    You said you would vote against #{incumbent} in November, whoever runs.

    Confirm it and you will be counted in #{seat_label}:

    #{url}

    Until you click that link you are not counted. We publish the number of
    people who committed in each district, never who they are.

    Didn't do this? Ignore this email and nothing happens.

    Vote No Incumbents
    No incumbents. No gerrymanders. Term limits. Leave the Supreme Court alone.
    """)
  end

  @doc """
  Sent when an already-confirmed address submits again — someone who lost
  their link, or a stranger typing an address that is not theirs. It
  carries no answers and no district count, only the way back in, so it
  tells a stranger nothing they did not already type.
  """
  def deliver_recovery(email, seat_label, url) do
    deliver(email, "Your commitment in #{seat_label}", """
    You are already counted in #{seat_label}.

    To review or withdraw your commitment:

    #{url}

    You can withdraw at any time and the count drops the same day.

    Vote No Incumbents
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(from())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end
end
