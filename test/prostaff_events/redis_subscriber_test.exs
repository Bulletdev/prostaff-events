defmodule ProstaffEvents.RedisSubscriberTest do
  use ExUnit.Case, async: true

  alias ProstaffEvents.RedisSubscriber

  defp event(overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "notification.created",
        "org_id" => "org-1",
        "user_id" => "user-1",
        "payload" => %{}
      },
      overrides
    )
  end

  describe "resolve_topics/1" do
    test "evento notification.* rota para notifications:{user_id} e org_events:{org_id}" do
      e = event(%{"type" => "notification.created"})
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))

      assert "org_events:org-1" in topics
      assert "notifications:user-1" in topics
      refute "inhouse:org-1" in topics
    end

    test "evento inhouse.* rota para inhouse:{org_id} e org_events:{org_id}" do
      e = event(%{"type" => "inhouse.session_started"})
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))

      assert "org_events:org-1" in topics
      assert "inhouse:org-1" in topics
      refute "notifications:user-1" in topics
    end

    test "evento tournament_match.* extrai tournament_id do payload" do
      e =
        event(%{"type" => "tournament_match.confirmed", "payload" => %{"tournament_id" => "t-99"}})

      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))

      assert "org_events:org-1" in topics
      assert "tournament:t-99" in topics
    end

    test "evento tournament_match.* sem tournament_id só rota para org_events" do
      e = event(%{"type" => "tournament_match.confirmed", "payload" => %{}})
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))

      assert topics == ["org_events:org-1"]
    end

    test "todos eventos rotam para org_events:{org_id}" do
      for type <- ["notification.x", "inhouse.y", "roster.z", "unknown.event"] do
        e = event(%{"type" => type})
        topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))
        assert "org_events:org-1" in topics, "esperava org_events para type=#{type}"
      end
    end

    test "retorna [] para evento sem campos obrigatórios" do
      assert [] = RedisSubscriber.resolve_topics(%{"type" => "something"})
      assert [] = RedisSubscriber.resolve_topics(%{})
    end

    test "aceita evento com version: \"1\"" do
      e = event(%{"version" => "1", "type" => "notification.created"})
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))
      assert "org_events:org-1" in topics
    end

    test "aceita evento sem campo version (backward compat)" do
      e = event()
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))
      assert "org_events:org-1" in topics
    end

    test "rejeita evento com version desconhecida" do
      e = event(%{"version" => "99"})
      assert [] = RedisSubscriber.resolve_topics(e)
    end

    test "mensagem de cada tópico é {:event, event}" do
      [{_topic, msg}] =
        RedisSubscriber.resolve_topics(%{
          "type" => "unknown",
          "org_id" => "org-1",
          "user_id" => "u"
        })

      assert {:event, _} = msg
    end
  end
end
