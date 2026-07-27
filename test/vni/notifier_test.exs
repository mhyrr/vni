defmodule VNI.NotifierTest do
  @moduledoc """
  The envelope, which Resend judges before it judges anything else: it
  refuses any address outside a domain verified in the account, so a
  hardcoded sender is a silent outage waiting for a domain change.
  """

  use VNI.DataCase, async: false

  import Swoosh.TestAssertions

  alias VNI.Pledges.Notifier

  setup do
    original = Application.get_env(:vni, Notifier)
    on_exit(fn -> Application.put_env(:vni, Notifier, original) end)
    %{original: original}
  end

  test "the sender comes from config, not from the module" do
    Application.put_env(:vni, Notifier, from: {"Test Sender", "hello@example.test"})

    {:ok, _email} =
      Notifier.deliver_confirmation(
        "voter@example.com",
        "OH-09",
        "Marcy Kaptur",
        "https://voteno.org/commitment/abc"
      )

    assert_email_sent(fn email ->
      assert email.from == {"Test Sender", "hello@example.test"}
    end)
  end

  test "both emails leave under the same envelope" do
    Application.put_env(:vni, Notifier, from: {"VNI", "commitments@example.test"})

    {:ok, _} = Notifier.deliver_confirmation("a@example.com", "OH-09", "Kaptur", "https://x/1")
    {:ok, _} = Notifier.deliver_recovery("b@example.com", "OH-09", "https://x/2")

    assert_email_sent(fn email -> assert email.from == {"VNI", "commitments@example.test"} end)
    assert_email_sent(fn email -> assert email.from == {"VNI", "commitments@example.test"} end)
  end

  test "the recovery mail tells a stranger nothing they did not already type" do
    {:ok, _} = Notifier.deliver_recovery("stranger@example.com", "OH-09", "https://x/2")

    assert_email_sent(fn email ->
      # No answers, no incumbent, no count — only the way back in.
      refute email.text_body =~ "Kaptur"
      assert email.text_body =~ "already counted in OH-09"
      assert email.text_body =~ "withdraw"
    end)
  end

  test "a configured sender is a well-formed envelope, whatever the domain" do
    assert {name, address} = Notifier.from()
    assert is_binary(name) and name != ""
    assert String.match?(address, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end
end
