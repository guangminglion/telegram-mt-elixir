defmodule MTProto.Session.Brain do
  require Logger
  alias MTProto.{AuthKey, Registry}

  @moduledoc false

  # Process a plain message
  def process(msg, session_id, :plain) do
    name = Map.get(msg, :name)

    case name do
      "resPQ" -> AuthKey.resPQ(msg, session_id)
      "server_DH_params_ok" -> AuthKey.server_DH_params_ok(msg, session_id)
      "server_DH_params_fail" -> AuthKey.server_DH_params_fail(msg, session_id)
      "dh_gen_ok" -> AuthKey.dh_gen_ok(msg, session_id)
      "dh_gen_fail" -> AuthKey.dh_gen_fail(msg, session_id)
      "dh_gen_retry" -> AuthKey.dh_gen_fail(msg, session_id)
      "error" ->
        if Map.get(msg, :code) == -404 do
          session = Registry.get(:session, session_id)
          dc = Registry.get(:dc, session.dc)
          if dc.auth_key == <<0::8*8>> do
            Logger.info "[Brain] I received a -404 error. I still don't have an auth key
            for this DC (#{dc.id}). Generating authorization key."
            AuthKey.req_pq(session_id)
          else
            Logger.warn "[Brain] Received error. I don't know what to do !"
          end
        end
      _ ->
        Logger.warn "[Brain] #{session_id} : received an unknow predicate #{name}."
    end
  end

  # Process an encrypted message
  def process_encrypted(message, session_id, :encrypted) do
    IO.inspect {session_id, message}
  end
end
