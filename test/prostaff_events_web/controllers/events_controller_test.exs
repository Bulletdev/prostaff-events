defmodule ProstaffEventsWeb.EventsControllerTest do
  use ProstaffEventsWeb.ConnCase

  setup do
    :ok
  end

  describe "GET /health" do
    test "retorna status ok", %{conn: conn} do
      conn = get(conn, "/health")
      assert json_response(conn, 200)["status"] == "ok"
      assert json_response(conn, 200)["service"] == "prostaff-events"
    end
  end

  describe "GET /health/ready" do
    test "retorna JSON com status e checks independente do estado da infra", %{conn: conn} do
      conn = get(conn, "/health/ready")
      # 200 se infra disponível, 503 caso contrário - ambos são válidos em test
      assert conn.status in [200, 503]
      body = json_response(conn, conn.status)
      assert is_binary(body["status"])
      assert is_map(body["checks"])
      assert Map.has_key?(body["checks"], "redis")
      assert Map.has_key?(body["checks"], "rails")
    end
  end

  describe "POST /events/notify" do
    test "aceita evento válido com X-API-Key correta", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test_scraper_key")
        |> post("/events/notify", %{"type" => "match.started", "org_id" => "org-1"})

      assert json_response(conn, 200)["ok"] == true
    end

    test "rejeita sem X-API-Key", %{conn: conn} do
      conn = post(conn, "/events/notify", %{"type" => "match.started", "org_id" => "org-1"})
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "rejeita com X-API-Key incorreta", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "wrong_key")
        |> post("/events/notify", %{"type" => "match.started", "org_id" => "org-1"})

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "rejeita payload sem type", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test_scraper_key")
        |> post("/events/notify", %{"org_id" => "org-1"})

      assert json_response(conn, 422)
    end

    test "rejeita payload sem org_id", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test_scraper_key")
        |> post("/events/notify", %{"type" => "match.started"})

      assert json_response(conn, 422)
    end

    test "aceita evento com version suportada", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test_scraper_key")
        |> post("/events/notify", %{
          "type" => "match.started",
          "org_id" => "org-1",
          "version" => "1"
        })

      assert json_response(conn, 200)["ok"] == true
    end

    test "rejeita evento com version desconhecida", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "test_scraper_key")
        |> post("/events/notify", %{
          "type" => "match.started",
          "org_id" => "org-1",
          "version" => "99"
        })

      assert json_response(conn, 422)
    end
  end
end
