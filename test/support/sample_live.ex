defmodule SampleLive do
  use Phoenix.LiveController

  defmodule BeforeGlobal do
    @behaviour Phoenix.LiveController.Plug

    @impl true
    def call(socket, payload) do
      assign(socket, :global_plug_called, payload)
    end

    def other(socket, _payload, arg) do
      assign(socket, :other_global_plug_called, arg)
    end
  end

  @impl true
  def apply_session(socket, session) do
    if session["user"] == "badguy",
      do: push_redirect(socket, to: "/"),
      else: assign(socket, user: session["user"])
  end

  plug BeforeGlobal
  plug {BeforeGlobal, :other}, :arg when type != :message and name != :index_with_opts

  plug :before_action_handler when type == :action
  plug :before_action_handler, :before_action_handler_called_two when type == :action

  defp before_action_handler(socket, %{params: params}, key \\ :before_action_handler_called) do
    history = Map.get(socket.assigns, :plug_history, [])

    if params["redirect"],
      do: push_redirect(socket, to: "/"),
      else: assign(socket, key, true) |> assign(:plug_history, history ++ [key])
  end

  plug :before_event_handler when type == :event

  def before_event_handler(socket, %{params: params}) do
    if params["redirect"],
      do: push_redirect(socket, to: "/"),
      else: assign(socket, before_event_handler_called: true)
  end

  plug :before_message_handler when type == :message

  def before_message_handler(socket, %{payload: message}) do
    if message == {:x, :redirect},
      do: push_redirect(socket, to: "/"),
      else: assign(socket, before_message_handler_called: true)
  end

  @impl true
  def action_handler(socket, name, params) do
    socket
    |> super(name, params)
    |> case do
      {:ok, socket, opts} -> {:ok, assign(socket, :action_handler_override, true), opts}
      socket -> assign(socket, :action_handler_override, true)
    end
  end

  @impl true
  def event_handler(socket, name, params) do
    socket
    |> super(name, params)
    |> assign(:event_handler_override, true)
  end

  @impl true
  def message_handler(socket, name, message) do
    socket
    |> super(name, message)
    |> assign(:message_handler_override, true)
  end

  @action_handler true
  def index(socket, params) do
    assign(socket, items: [params["first_item"], :second])
  end

  @action_handler true
  def index_with_opts(socket, params) do
    socket = assign(socket, items: [params["first_item"], :second])
    {:ok, socket, temporary_assigns: [items: []]}
  end

  @event_handler true
  def create(socket, params) do
    assign(socket, items: socket.assigns.items ++ [params["new_item"]])
  end

  @message_handler true
  def x(socket, _message) do
    assign(socket, called: true)
  end
end
