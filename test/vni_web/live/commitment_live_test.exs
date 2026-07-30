defmodule VNIWeb.CommitmentLiveTest do
  use VNIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias VNI.{Atlas, Pledges, Politics, Scores}

  setup do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: "OH",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/",
        authority: :legislature,
        controlling_party: :rep,
        authorship_source_url: "https://redistricting.lls.edu/state/ohio/"
      })

    {:ok, district} =
      Atlas.upsert_district(map_version, %{
        state: "OH",
        number: 9,
        geom: %Geo.MultiPolygon{
          coordinates: [
            [[{-83.5, 41.6}, {-83.3, 41.6}, {-83.3, 41.8}, {-83.5, 41.8}, {-83.5, 41.6}]]
          ],
          srid: 4326
        }
      })

    {:ok, _profile} =
      Politics.upsert_profile(district, %{
        incumbent_name: "Marcy Kaptur",
        incumbent_party: :dem,
        incumbent_since: 1983,
        last_margin_pct: 0.9,
        last_margin_votes: 2_382,
        last_votes_cast: 264_000,
        last_margin_cycle: 2024,
        last_margin_party: :dem,
        margin_source_url: "https://doi.org/10.7910/DVN/IG0UN2"
      })

    :ok = Scores.score_current!()

    %{district: Atlas.get_district_by_slug("oh-9")}
  end

  defp fill(view, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "commitment" => "yes",
          "voted_for_incumbent" => "yes",
          "party" => "democrat",
          "email" => "voter@example.com"
        },
        overrides
      )

    view |> form("#commitment-form", commitment: params) |> render_submit()
  end

  describe "the ask" do
    test "names the seat and its incumbent without naming anyone running against them",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/districts/oh-9/join")

      assert html =~ "Marcy Kaptur"
      assert html =~ "in November"
      assert html =~ "This seat was decided by 2,382 votes"
      assert has_element?(view, "#commitment-form")

      # Doctrine: no challenger, ever, on any surface reached from a district.
      refute html =~ "challenger"
    end

    test "records a commitment, mails a link, and counts nobody yet", %{conn: conn, district: d} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")

      html = fill(view)
      assert html =~ "Check your email"
      assert html =~ "voter@example.com"

      assert_email_sent(fn email ->
        assert email.subject =~ "Confirm your commitment in OH-09"
        assert email.text_body =~ "Marcy Kaptur"
      end)

      # Double opt-in: the submission alone moves nothing.
      assert Pledges.committed_count(d.id) == 0
    end

    test "a bad address is reported on the form rather than silently dropped", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")

      html = fill(view, %{"email" => "nope@mailinator.com"})
      assert html =~ "Use an address you can actually receive mail at"
      refute html =~ "Check your email"
    end

    test "an unknown district does not offer an ask", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/districts"}}} = live(conn, ~p"/districts/zz-99/join")
    end
  end

  describe "confirmation" do
    test "the link confirms, counts, and says what the person just did", %{
      conn: conn,
      district: d
    } do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)
      token = sent_token()

      {:ok, _view, html} = live(conn, ~p"/commitment/#{token}")

      assert Pledges.committed_count(d.id) == 1
      assert html =~ "You&#39;re in."
      # Democrat, Democratic incumbent: the case the project exists for.
      assert html =~ "vote out an incumbent of your own party"
    end

    test "committing against the other party is named as the free choice it is",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view, %{"party" => "republican"})

      {:ok, _view, html} = live(conn, ~p"/commitment/#{sent_token()}")

      # Named as easy without being taken back — the harder case is put
      # as a question rather than as a scolding.
      assert html =~ "so this one was easy"
      assert html =~ "it still counts"
      assert html =~ "what you&#39;d do if your side did"
    end

    test "declining to state a party gets neither line", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view, %{"party" => "declined"})

      {:ok, _view, html} = live(conn, ~p"/commitment/#{sent_token()}")

      refute html =~ "your own party"
      refute html =~ "so this one was easy"
    end

    test "clicking the link twice is not an error", %{conn: conn, district: d} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)
      token = sent_token()

      {:ok, _view, _html} = live(conn, ~p"/commitment/#{token}")
      {:ok, _view, html} = live(conn, ~p"/commitment/#{token}")

      assert html =~ "You&#39;re in."
      assert Pledges.committed_count(d.id) == 1
    end

    test "a stale or invented token explains itself", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/commitment/not-a-real-token")

      assert has_element?(view, "#commitment-missing")
      assert render(view) =~ "can&#39;t find that commitment"
    end
  end

  describe "withdrawal" do
    test "drops out of the count from the same link", %{conn: conn, district: d} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)

      {:ok, view, _html} = live(conn, ~p"/commitment/#{sent_token()}")
      assert Pledges.committed_count(d.id) == 1

      html = view |> element("#withdraw-commitment") |> render_click()

      assert html =~ "out of the count"
      assert Pledges.committed_count(d.id) == 0
    end
  end

  describe "re-submission" do
    test "an already-confirmed address gets a recovery link, not a second row",
         %{conn: conn, district: d} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)
      {:ok, _view, _html} = live(conn, ~p"/commitment/#{sent_token()}")

      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view, %{"commitment" => "no", "party" => "republican"})

      assert_email_sent(fn email ->
        assert email.subject =~ "Your commitment in OH-09"
        # The recovery mail tells a stranger nothing they did not type.
        refute email.text_body =~ "Republican"
        refute email.text_body =~ "Marcy Kaptur"
        true
      end)

      # The answers stand, and so does the count.
      assert Pledges.committed_count(d.id) == 1
      assert VNI.Repo.aggregate(VNI.Pledges.Pledge, :count) == 1
    end
  end

  # The magic link only ever exists in the mail, which is where a reader
  # would find it too.
  describe "the share card" do
    test "hands over a card built from the seat's own facts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)

      {:ok, view, html} = live(conn, ~p"/commitment/#{sent_token()}")

      assert has_element?(view, "#commitment-share canvas[width='1080'][height='1920']")
      assert html =~ "HELD"
      assert html =~ "Decided by 2,382 votes in 2024."
      assert has_element?(view, "#commitment-share [data-share]")
      assert has_element?(view, "#commitment-share [data-download]")
    end

    test "the X link posts the district page, and names no one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)

      {:ok, view, _html} = live(conn, ~p"/commitment/#{sent_token()}")

      href = view |> element("#commitment-share-x") |> render() |> intent_href()
      query = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert query["url"] =~ "/districts/oh-9"
      assert query["text"] =~ "Everyone hates Congress but incumbents still win."
      refute query["text"] =~ "Kaptur"

      # Sized for a free X account's 280, not Premium's 25,000 — the link
      # costs 23 of them however long it is.
      assert String.length(query["text"]) + 24 <= 280
    end

    # The site's own copy promises counts and never people. A shared
    # artifact is the one place that promise is tested in public, so the
    # token has to be absent from everything the page hands out — not
    # filtered out of it later.
    test "nothing shareable carries the token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)
      token = sent_token()

      {:ok, view, _html} = live(conn, ~p"/commitment/#{token}")

      share_block = view |> element("#commitment-share") |> render()

      refute share_block =~ token
    end

    test "a withdrawn commitment is not offered a card to post", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9/join")
      fill(view)

      {:ok, view, _html} = live(conn, ~p"/commitment/#{sent_token()}")
      view |> element("#withdraw-commitment") |> render_click()

      refute has_element?(view, "#commitment-share")
    end
  end

  defp intent_href(html) do
    [href] = Regex.run(~r/href="([^"]*x\.com[^"]*)"/, html, capture: :all_but_first)

    href |> String.replace("&amp;", "&")
  end

  defp sent_token do
    assert_email_sent(fn email ->
      assert [[_, token]] = Regex.scan(~r{/commitment/([\w\-]+)}, email.text_body)
      send(self(), {:token, token})
    end)

    receive do
      {:token, token} -> token
    end
  end
end
