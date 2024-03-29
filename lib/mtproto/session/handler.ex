defmodule MTProto.Session.Handler do
  require Logger
  alias MTProto.{TCP, Registry, Crypto, Session, Payload}
  alias MTProto.Session.Brain

  @moduledoc false

  def start_link(session_id, dc_id) do
    GenServer.start_link(__MODULE__, {session_id, dc_id}, [])
  end

  # Initialize the handler
  def init({session_id, dc_id}) do
    Logger.debug "[Handler] #{session_id} : starting handler."

    Registry.set :session, session_id, %Session{handler: self(), dc: dc_id}

    {:ok, session_id}
  end

  # Send a plain message
  def handle_call({:send_plain, payload}, _from, session_id) do
    reply = send_plain(payload, session_id)
    {:reply, reply, session_id}
  end

  # Send an encrypted_message
  def handle_call({:send, payload}, _from, session_id) do
    reply = send_encrypted(payload, session_id)
    {:reply, reply, session_id}
  end

  def send_plain(payload, session_id) do
    session = Registry.get :session, session_id

    payload |> TCP.wrap(session.seqno) |> TCP.send(session.socket)

    # Update the sequence number
    Registry.set :session, session_id, :seqno, session.seqno + 1
  end

  def send_encrypted(payload, session_id) do
    session = Registry.get :session, session_id
    dc = Registry.get :dc, session.dc

    if dc.auth_key != <<0::8*8>> && dc.auth_key != nil do
      # Set the msg_seqno
      msg_seqno = (session.msg_seqno * 2 + 1)
      msg_seqno = msg_seqno |> TL.serialize(:int)

      payload = :binary.part(payload, 0, 8) <> msg_seqno
                                            <> :binary.part(payload, 12, byte_size(payload) - 12)

      encrypted_msg = Crypto.encrypt_message(dc.auth_key, dc.server_salt, session_id, payload)
      encrypted_msg |> TCP.wrap(session.seqno) |> TCP.send(session.socket)

      # Update the sequence numbers
      Registry.set(:session, session_id, :msg_seqno, session.msg_seqno + 1)
      Registry.set :session, session_id, :seqno, session.seqno + 1
    else
      {:error, "Auth key does not exist"}
    end
  end

  # Receive a message, parse and dispatch.
  def handle_info({:recv, payload}, session_id) do
    session = Registry.get :session, session_id
    cond do
      # Error message (4 bytes)
      byte_size(payload) == 4 ->
        error = :binary.part(payload, 0, 4) |> TL.deserialize(:meta32)
        Logger.warn "[Handler] #{session_id} : received error #{error}."
        Brain.process(%{name: "error", code: error}, session_id, :plain)
      byte_size(payload) >= 8 ->
        auth_key = :binary.part(payload, 0, 8)

        # authorization key composed of 8 <<0>> : plain message.
        if auth_key == <<0::8*8>> do
          {map, _} = payload |> Payload.parse(:plain)
          Brain.process(map, session_id, :plain)
        else
          # Encrypted message
          dc = Registry.get :dc, session.dc

          decrypted = payload |> Crypto.decrypt_message(dc.auth_key)
#          msg_seqno = :binary.part(decrypted, 24, 4) |> TL.deserialize(:int)
#          msg_seqno = round(msg_seqno/2)
#          Logger.debug "[RECEIVED] Message sequence number : #{msg_seqno}"
#          if session.msg_seqno <  msg_seqno do
#            Logger.warn "[MSG_SEQNO] Override local #{session.msg_seqno} with #{msg_seqno}"
#            Registry.set(:session, session_id, :msg_seqno, msg_seqno)
#          end
          {map, _} = decrypted |> Payload.parse(:encrypted)
          Brain.process(map, session_id, :encrypted)
        end
      true ->
        Logger.error "[Handler] #{session_id} : received unknow message."
    end

    {:noreply, session_id}
  end

  def terminate(reason, state) do
    Logger.debug "[Handler] #{state} : terminating handler."
    {:error, state}
  end
end
