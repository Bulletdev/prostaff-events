defmodule ProstaffEvents.RedisSubscriberTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  # US-08 subiu o ramo nao roteado para warning; sem isto ele polui a saida
  # dos testes que nao estao olhando log. Falha ainda mostra tudo.
  @moduletag :capture_log

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

    test "aceita version inteiro, que e como o Rails serializa o campo" do
      e = event(%{"version" => 1, "type" => "notification.created"})
      topics = RedisSubscriber.resolve_topics(e) |> Enum.map(&elem(&1, 0))

      assert "org_events:org-1" in topics
      assert "notifications:user-1" in topics
    end

    test "rejeita version inteiro desconhecido, nao so a string" do
      e = event(%{"version" => 2})
      assert RedisSubscriber.resolve_topics(e) == []
    end
  end

  describe "motivo do descarte" do
    test "versao nao suportada loga rejeicao por versao, nao campos ausentes" do
      log = capture_log(fn -> send_event(event(%{"version" => 99})) end)

      assert log =~ "unsupported version"
      refute log =~ "missing or invalid field"
    end

    test "campo obrigatorio ausente loga qual campo faltou" do
      log = capture_log(fn -> send_event(Map.delete(event(), "user_id")) end)

      assert log =~ "missing or invalid field"
      assert log =~ "user_id"
      refute log =~ "unsupported version"
    end

    test "type nao-string e tratado como campo invalido, sem derrubar o processo" do
      e = event(%{"type" => 123})

      assert RedisSubscriber.resolve_topics(e) == []
      assert capture_log(fn -> send_event(e) end) =~ "type"
    end

    test "nenhum dos logs de descarte imprime o payload" do
      segredo = "nao-pode-vazar-no-log"
      pid = start_subscriber()

      for e <- [
            event(%{"version" => 99, "payload" => %{"email" => segredo}}),
            Map.delete(event(%{"payload" => %{"email" => segredo}}), "org_id")
          ] do
        refute capture_log(fn -> send_event(pid, e) end) =~ segredo
      end
    end

    test "tipo sem rota especifica loga em warning, nao em debug" do
      log = capture_log(fn -> send_event(event(%{"type" => "roster.player_hired"})) end)

      assert log =~ "[warning]"
      assert log =~ "Unrouted event"
      assert log =~ "roster.player_hired"
    end
  end

  # route_event/1 e privado; o caminho publico e a mensagem do Redix. O
  # subscriber registra com name: __MODULE__, entao e um por teste.
  defp start_subscriber, do: start_supervised!({RedisSubscriber, []}, restart: :temporary)

  defp send_event(event), do: send_event(start_subscriber(), event)

  defp send_event(pid, event) do
    send(pid, {:redix_pubsub, nil, nil, :pmessage, %{payload: Jason.encode!(event)}})
    # get_state serializa: quando retorna, o handle_info do evento ja terminou.
    _ = :sys.get_state(pid)
    :ok
  end
end
