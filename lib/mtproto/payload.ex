defmodule MTProto.Payload do
  @moduledoc """
  Utils to encode/decode and wrap/unwrap payloads.

  Note that a payload has a different structure if it is designed to be send
  encrypted or not. See [the detailed description of MTProto](https://core.telegram.org/mtproto/description)
  for more information.
  """

  @doc """
  Build and wrap (`type` is either `:plain` or `:encrypted`) a TL object,
  given its constructor and parameters.
  """
  def build(method, args, type \\ :encrypted) do
    TL.build(method, args) |> wrap(type)
  end

  @doc """
  Unwrap ('type' is either `:plain` or `:encrypted`) and parse a message.
  Returns `{map, tail}`.
  """
  def parse(msg, type \\ :encrypted) do
    #auth_key_id = :binary.part(msg, 0, 8)
    map = msg |> unwrap(type)
    container = Map.get map, :constructor
    content = Map.get map, :message_content
    TL.parse(container, content)
  end

  @doc """
    Wrap a message as a 'plain' payload.
  """
  def wrap(msg, :plain) do
    auth_id_key = 0
    msg_id =  generate_id()
    msg_len = byte_size(msg)
    TL.serialize(auth_id_key, :meta64) <> TL.serialize(msg_id, :meta64)
                                       <> TL.serialize(msg_len, :meta32)
                                       <> msg
  end

  @doc """
    Wrap a message as an 'encrypted' payload.
  """
  def wrap(msg, :encrypted) do
    msg_id = generate_id()
    seq_no = 0 # See the handler
    msg_len = byte_size(msg)

    TL.serialize(msg_id, :meta64) <> TL.serialize(seq_no, :meta32)
                                  <> TL.serialize(msg_len, :meta32)
                                  <> msg
  end

  @doc """
    Unwrap a 'plain' payload.
  """
  def unwrap(msg, :plain) do
    auth_key_id = :binary.part(msg, 0, 8) |> TL.deserialize(:long)
    messsage_id = :binary.part(msg, 8, 8) |> TL.deserialize(:long)
    message_data_length = :binary.part(msg, 16, 4) |> TL.deserialize(:meta32)
    message_data = :binary.part(msg, 20, message_data_length)

    constructor = :binary.part(message_data, 0, 4) |> TL.deserialize(:meta32)
    message_content = :binary.part(message_data, 4, message_data_length - 4)

    %{
      auth_key_id: auth_key_id,
      message_id: messsage_id,
      message_data_length: message_data_length,
      constructor: constructor,
      message_content: message_content
    }
  end

  @doc """
    Unwrap an 'encrypted' payload.
  """
  def unwrap(msg, :encrypted) do
    salt = :binary.part(msg, 0, 8) |> TL.deserialize(:long)
    session_id = :binary.part(msg, 8, 8) |> TL.deserialize(:long)
    message_id = :binary.part(msg, 16, 8) |> TL.deserialize(:long)
    seq_no =:binary.part(msg, 24, 4) |> TL.deserialize(:meta32)
    message_data_length =  :binary.part(msg, 28, 4) |> TL.deserialize(:meta32)
    message_data = :binary.part(msg, 32, message_data_length)

    constructor = :binary.part(message_data, 0, 4) |> TL.deserialize(:meta32)
    message_content = :binary.part(message_data, 4, message_data_length - 4)
    %{
      salt: salt,
      session_id: session_id,
      message_id: message_id,
      seq_no: seq_no,
      messsage_data_length: message_data_length,
      constructor: constructor,
      message_content: message_content
    }
  end

  # Generate id for messages,  Unix time * 2^32
  defp generate_id do
    :os.system_time(:seconds) * :math.pow(2,32) |> round
  end
end
