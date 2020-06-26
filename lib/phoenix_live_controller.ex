defmodule Phoenix.LiveController do
  @moduledoc ~S"""
  Controller-style abstraction for building multi-action live views on top of `Phoenix.LiveView`.

  `Phoenix.LiveView` API differs from `Phoenix.Controller` API in order to emphasize stateful
  lifecycle of live views, support long-lived processes behind them and accommodate their much
  looser ties with the router. Contrary to HTTP requests that are rendered and discarded, live
  actions are mounted and their processes stay alive to handle events & miscellaneous process
  interactions and to re-render as many times as necessary. Because of these extra complexities, the
  library drives developers towards single live view per router action.

  At the same time, `Phoenix.LiveView` provides a complete solution for router-aware live navigation
  and it introduces the concept of live actions both in routing and in the live socket. These
  features mean that many live views may play a role similar to classic controllers.

  It's all about efficient code organization - just like a complex live view's code may need to be
  broken into multiple modules or live components, a bunch of simple live actions centered around
  similar topic or resource may be best organized into a single live view module, keeping the
  related web logic together and giving the room to share common code. That's where
  `Phoenix.LiveController` comes in: to organize live view code that covers multiple live actions in
  a fashion similar to how Phoenix controllers organize multiple HTTP actions. It provides a
  pragmatic convention that still keeps pieces of a stateful picture visible by enforcing clear
  function annotations.

  Here's an exact live equivalent of an HTML controller generated with the `mix phx.gen.html Blog
  Article articles ...` scaffold, powered by `Phoenix.LiveController`:

      # lib/my_app_web.ex
      defmodule MyAppWeb do
        def live_controller do
          quote do
            use Phoenix.LiveController
            alias MyAppWeb.Router.Helpers, as: Routes
          end
        end
      end

      # lib/my_app_web/router.ex
      defmodule MyAppWeb.Router do
        scope "/", MyAppWeb do
          live "/articles", ArticleLive, :index
          live "/articles/new", ArticleLive, :new
          live "/articles/:id", ArticleLive, :show
          live "/articles/:id/edit", ArticleLive, :edit
        end
      end

      # lib/my_app_web/live/article_live.ex
      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        alias MyApp.Blog
        alias MyApp.Blog.Article

        @action_handler true
        def index(socket, _params) do
          articles = Blog.list_articles()
          assign(socket, articles: articles)
        end

        @action_handler true
        def new(socket, _params) do
          changeset = Blog.change_article(%Article{})
          assign(socket, changeset: changeset)
        end

        @event_handler true
        def create(socket, %{"article" => article_params}) do
          case Blog.create_article(article_params) do
            {:ok, article} ->
              socket
              |> put_flash(:info, "Article created successfully.")
              |> push_redirect(to: Routes.article_path(socket, :show, article))

            {:error, %Ecto.Changeset{} = changeset} ->
              assign(socket, changeset: changeset)
          end
        end

        @action_handler true
        def show(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          assign(socket, article: article)
        end

        @action_handler true
        def edit(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          changeset = Blog.change_article(article)
          assign(socket, article: article, changeset: changeset)
        end

        @event_handler true
        def update(socket, %{"article" => article_params}) do
          article = socket.assigns.article

          case Blog.update_article(article, article_params) do
            {:ok, article} ->
              socket
              |> put_flash(:info, "Article updated successfully.")
              |> push_redirect(to: Routes.article_path(socket, :show, article))

            {:error, %Ecto.Changeset{} = changeset} ->
              assign(socket, article: article, changeset: changeset)
          end
        end

        @event_handler true
        def delete(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          {:ok, _article} = Blog.delete_article(article)

          socket
          |> put_flash(:info, "Article deleted successfully.")
          |> push_redirect(to: Routes.article_path(socket, :index))
        end
      end

  `Phoenix.LiveController` is not meant to be a replacement of `Phoenix.LiveView` - although most
  live views may be represented with it, it will likely prove beneficial only for specific kinds of
  live views. These include live views with following traits:

  * Orientation around same resource, e.g. web code for specific context like in `mix phx.gen.html`
  * Mounting or event handling code that's mostly action-specific
  * Param handling code that's action-specific and prevails over global mounting code
  * Common redirecting logic executed before mounting or event handling, e.g. auth logic

  ## Mounting actions

  *Action handlers* replace `c:Phoenix.LiveView.mount/3` entry point in order to split mounting of
  specific live actions into separate functions. They are annotated with `@action_handler true` and,
  just like with Phoenix controller actions, their name is the name of the action they mount.

      # lib/my_app_web/router.ex
      defmodule MyAppWeb.Router do
        scope "/", MyAppWeb do
          live "/articles", ArticleLive, :index
          live "/articles/:id", ArticleLive, :show
        end
      end

      # lib/my_app_web/live/article_live.ex
      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @action_handler true
        def index(socket, _params) do
          articles = Blog.list_articles()
          assign(socket, articles: articles)
        end

        @action_handler true
        def show(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          assign(socket, article: article)
        end
      end

  Note that action handlers don't have to wrap the resulting socket in the `{:ok, socket}` tuple,
  which also brings them closer to Phoenix controller actions.

  ## Handling events

  *Event handlers* replace `c:Phoenix.LiveView.handle_event/3` callbacks in order to make the event
  handling code consistent with the action handling code. These functions are annotated with
  `@event_handler true` and their name is the name of the event they handle.

      # lib/my_app_web/templates/article/*.html.leex
      <%= link "Delete", to: "#", phx_click: :delete, phx_value_id: article.id, data: [confirm: "Are you sure?"] %>

      # lib/my_app_web/live/article_live.ex
      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @event_handler true
        def delete(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          {:ok, _article} = Blog.delete_article(article)

          socket
          |> put_flash(:info, "Article deleted successfully.")
          |> push_redirect(to: Routes.article_path(socket, :index))
        end
      end

  Note that, consistently with action handlers, event handlers don't have to wrap the resulting
  socket in the `{:noreply, socket}` tuple.

  Also note that, as a security measure, LiveController won't convert binary names of events that
  don't have corresponding event handlers into atoms that wouldn't be garbage collected.

  ## Handling process messages

  *Message handlers* offer an alternative (but not a replacement) to
  `c:Phoenix.LiveView.handle_info/2` for handling process messages in a fashion consistent with
  action and event handlers. These functions are annotated with `@message_handler true` and their
  name equals to a message atom (e.g. `:refresh_article`) or to an atom placed as first element in a
  message tuple (e.g. `{:article_update, ...}`).

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @action_handler true
        def show(socket, %{"id" => id}) do
          :timer.send_interval(5_000, self(), :refresh_article)
          assign(socket, article: Blog.get_article!(id))
        end

        @message_handler true
        def refresh_article(socket, _message) do
          assign(socket, article: Blog.get_article!(socket.assigns.article.id))
        end
      end

   Support for handling messages wrapped in tuples allows to incorporate `Phoenix.PubSub` in
   live controllers in effortless and consistent way.

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller
        alias Phoenix.PubSub

        @action_handler true
        def show(socket, %{"id" => id}) do
          article = Blog.get_article!(id)
          PubSub.subscribe(MyApp.PubSub, "article:#{article.id}")
          assign(socket, article: Blog.get_article!(id))
        end

        @message_handler true
        def article_update(socket, {_, article}) do
          assign(socket, article: article)
        end

        @event_handler true
        def update(socket = %{assigns: %{article: article}}, %{"article" => article_params}) do
          article = socket.assigns.article

          case Blog.update_article(article, article_params) do
            {:ok, article} ->
              PubSub.broadcast(MyApp.PubSub, "article:#{article.id}", {:article_update, article})

              socket
              |> put_flash(:info, "Article updated successfully.")
              |> push_redirect(to: Routes.article_path(socket, :show, article))

            {:error, %Ecto.Changeset{} = changeset} ->
              assign(socket, article: article, changeset: changeset)
          end
        end

  For messages that can't be handled by message handlers, a specific implementation of
  `c:Phoenix.LiveView.handle_info/3` may still be provided.

  Note that, consistently with action & event handlers, message handlers don't have to wrap the
  resulting socket in the `{:noreply, socket}` tuple.

  ## Applying session

  Session, previously passed to `c:Phoenix.LiveView.mount/3`, is not passed through to action
  handlers. Instead, an optional `c:apply_session/2` callback may be defined in order to read the
  session and modify socket before an actual action handler is called.

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @impl true
        def apply_session(socket, session) do
          user_token = session["user_token"]
          user = user_token && Accounts.get_user_by_session_token(user_token)

          assign(socket, current_user: user)
        end

        # ...
      end

  Note that, in a fashion similar to controller plugs, no further action handling logic will be
  called if the returned socket was redirected - more on that below.

  ## Updating params without redirect

  For live views that [implement parameter
  patching](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-live-navigation) (e.g.
  to avoid re-mounting the live view & resetting its DOM or state), action handlers also replace
  `c:Phoenix.LiveView.handle_params/3` callbacks. The same action handler is called once when
  mounting and then it's called again whenever params are patched.

  This means that parameter patching is supported out-of-the-box for action handlers that work just
  as fine for initial mount as for subsequent parameter changes.

      # lib/my_app_web/templates/article/index.html.leex
      <%= live_patch "Page 2", to: Routes.article_path(@socket, :index, page: "2") %>

      # lib/my_app_web/live/article_live.ex
      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @action_handler true
        def index(socket, params) do
          articles = Blog.list_articles(page: params["page"])
          assign(socket, articles: articles)
        end
      end

  Using the `mounted?/1` helper, action handlers may conditionally invoke parts of their logic
  depending on whether socket was already mounted, e.g. to initiate timers or run expensive loads
  that don't depend on params only upon the first mount.

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @action_handler true
        def index(socket, params) do
          if connected?(socket) && !mounted?(socket),
            do: :timer.send_interval(5_000, self(), :check_for_new_articles)

          socket = unless mounted?(socket),
            do: assign(socket, tags: Blog.list_tags()),
            else: socket

          articles = Blog.list_articles(page: params["page"])
          assign(socket, articles: articles)
        end
      end

  Note that an action handler will only be called once when mounting, even though native LiveView
  calls both `mount/3` and `handle_params/3` at that moment.

  ## Chaining & plugs

  Phoenix controllers are [backed by the power of Plug
  pipelines](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-plug-pipeline) in order to
  organize common code called before actions and to allow halting early. LiveController provides
  similar solution for these problems via `plug/1` macro supported by the `chain/2`
  helper function.

  `plug/1` allows to define callbacks that are called in a chain in order to act on a socket before
  an actual action, event or message handler is called:

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        plug :require_authenticated_user

        defp require_authenticated_user(socket = %{assigns: %{current_user: user}}) do
          if user do
            socket
          else
            socket
            |> put_flash(:error, "You must log in first.")
            |> push_redirect(to: "/")
          end
        end
      end

  There are multiple ways to specify plug callback:

  - `plug :require_authenticated_user` - calls local function with `socket` argument
  - `plug LiveUserAuth` - calls external module's `call` function with `socket` argument
  - `plug {LiveUserAuth, :require_authenticated_user}` - calls external function with `socket` argument
  - `plug require_authenticated_user(...args)` - calls local function with arbitrary args
  - `plug LiveUserAuth.require_authenticated_user(...args)` - calls external function with arbitrary args

  > **Note**: `Phoenix.LiveController.Plug` behaviour is available for defining module plugs that
  > are expected to expose a single `call(socket)` plug function (second case above).

  It's possible to scope given plug to only a subset of handlers with the `when` condition:

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        plug :require_authenticated_user when action not in [:index, :show]
      end

  Following variables may be referenced when specifying arbitrary arguments or the `when`
  condition:

  * `action` / `event` / `message` - action, event or message handler name (atom or `nil`)
  * `socket` - current LiveView socket (`Phoenix.LiveView.Socket` struct)
  * `params` - action or event params (map or `nil`)
  * `payload` - message payload (message supported by message handler or `nil`)

  All plug forms may be freely mixed with the `when` conditions:

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        plug require_user_role(socket, :admin)
        plug fetch_own_article(socket, params) when action in [:edit] or event in [:update, :delete]

        defp require_user_role(socket = %{assigns: %{current_user: user}}, required_role) do
          if user.role == required_role do
            socket
          else
            socket
            |> put_flash(:error, "You must be #{required_role} in order to continue.")
            |> push_redirect(to: "/")
          end
        end

        defp fetch_own_article(
          socket = %{assigns: %{current_user: %{id: user_id}}},
          %{"id" => article_id}
        ) do
          case Blog.get_article!(id) do
            article = %{author_id: ^user_id} ->
              assign(socket, :article, article)

            _ ->
              socket
              |> put_flash(:error, "You can't modify someone else's article.")
              |> push_redirect(to: "/")
          end
        end
      end

  > **Pro tip**: Condition in `when` is not a guard, therefore it's possible to call any function
  > within it. That makes it easy for example to only call a plug upon mounting and not when
  > params are getting patched:
  >
  > ```
  > plug fetch_article(socket, params) when not mounted?(socket)
  > ```

  If multiple plugs are defined, they'll be called in a chain. If any of them redirects the socket
  or returns a tuple instead of just socket then the chain will be halted, which will also prevent
  action, event or message handler from being called.

  This is guaranteed by internal use of the `chain/2` function. This simple helper calls
  any function that takes socket as argument & that returns it only if the socket wasn't previously
  redirected or wrapped in a tuple and passes the socket through otherwise. It may also be used
  inside a plug or handler code for a similar result:

      defmodule MyAppWeb.ArticleLive do
        use MyAppWeb, :live_controller

        @action_handler true
        def edit(socket, %{"id" => id}) do
          socket
          |> require_authenticated_user()
          |> chain(&assign(&1, article: Blog.get_article!(id)))
          |> chain(&authorize_article_author(&1, &1.assigns.article))
          |> chain(&assign(&1, changeset: Blog.change_article(&.assigns.article)))
        end
      end

  After all plugs are called without halting the chain, `c:action_handler/3`, `c:event_handler/3`
  and `c:message_handler/3` - rough equivalents of
  [`action/2`](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-overriding-action-2-for-custom-arguments)
  plug in Phoenix controllers - complete the pipeline by calling functions named after specific
  actions, events or messages.

  ## Specifying LiveView options

  Any options that were previously passed to `use Phoenix.LiveView`, such as `:layout` or
  `:container`, may now be passed to `use Phoenix.LiveController`.

      use Phoenix.LiveController, layout: {MyAppWeb.LayoutView, "live.html"}

  ## Rendering actions

  Implementation of the `c:Phoenix.LiveView.render/1` callback may be omitted in which case the
  default implementation will be injected. It'll ask the view module named after specific live
  module to render HTML template named after the action - the same way that Phoenix controllers do
  when the `Phoenix.Controller.render/2` is called without a template name.

  For example, `MyAppWeb.ArticleLive` mounted with `:index` action will render with following call:

      MyAppWeb.ArticleView.render("index.html", assigns)

  Custom `c:Phoenix.LiveView.render/1` implementation may still be provided if necessary.

  """

  alias Phoenix.LiveView.Socket

  @doc ~S"""
  Allows to read the session and modify socket before an actual action handler is called.

  Read more about how to apply the session and the consequences of returning redirected socket from
  this callback in docs for `Phoenix.LiveController`.
  """
  @callback apply_session(
              socket :: Socket.t(),
              session :: map
            ) :: Socket.t()

  @doc ~S"""
  Invokes action handler for specific action.

  It can be overridden, e.g. in order to modify the list of arguments passed to action handlers.

      @impl true
      def action_handler(socket, name, params) do
        apply(__MODULE__, name, [socket, params, socket.assigns.current_user])
      end

  It can be wrapped, e.g. for sake of logging or modifying the socket returned from action handlers.

      @impl true
      def action_handler(socket, name, params) do
        Logger.debug("#{__MODULE__} started handling #{name}")
        socket = super(socket, name, params)
        Logger.debug("#{__MODULE__} finished handling #{name}")
        socket
      end

  Read more about the role that this callback plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.

  """
  @callback action_handler(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) ::
              Socket.t()
              | {:ok, Socket.t()}
              | {:ok, Socket.t(), keyword()}
              | {:noreply, Socket.t()}

  @doc ~S"""
  Invokes event handler for specific event.

  It works in a analogous way and opens analogous possibilities to `c:action_handler/3`.

  Read more about the role that this callback plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  @callback event_handler(
              socket :: Socket.t(),
              name :: atom,
              params :: Socket.unsigned_params()
            ) :: Socket.t() | {:ok, Socket.t()}

  @doc ~S"""
  Invokes message handler for specific message.

  It works in a analogous way and opens analogous possibilities to `c:action_handler/3`.

  Read more about the role that this callback plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  @callback message_handler(
              socket :: Socket.t(),
              name :: atom,
              message :: any
            ) :: Socket.t() | {:noreply, Socket.t()}

  @optional_callbacks apply_session: 2,
                      action_handler: 3,
                      event_handler: 3,
                      message_handler: 3

  defmodule Plug do
    @moduledoc """
    Defines plug module for use with Phoenix live controllers.
    """

    @callback call(socket :: Socket.t()) ::
                Socket.t()
                | {:ok, Socket.t()}
                | {:ok, Socket.t(), keyword()}
                | {:noreply, Socket.t()}
  end

  defmacro __using__(opts) do
    view_module =
      __CALLER__.module
      |> to_string()
      |> String.replace(~r/(Live|LiveController)$/, "")
      |> Kernel.<>("View")
      |> String.to_atom()

    quote do
      use Phoenix.LiveView, unquote(opts)

      @behaviour unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :actions, accumulate: true)
      Module.register_attribute(__MODULE__, :events, accumulate: true)
      Module.register_attribute(__MODULE__, :messages, accumulate: true)
      Module.register_attribute(__MODULE__, :plugs, accumulate: true)

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      import unquote(__MODULE__)

      # Implementations of Phoenix.LiveView callbacks

      def mount(params, session, socket),
        do:
          unquote(__MODULE__)._mount(
            __MODULE__,
            &__live_controller_before__/3,
            params,
            session,
            socket
          )

      def handle_params(params, url, socket),
        do:
          unquote(__MODULE__)._handle_params(
            __MODULE__,
            &__live_controller_before__/3,
            params,
            url,
            socket
          )

      def handle_event(event_string, params, socket),
        do:
          unquote(__MODULE__)._handle_event(
            __MODULE__,
            &__live_controller_before__/3,
            event_string,
            params,
            socket
          )

      def render(assigns = %{live_action: action}),
        do: unquote(view_module).render("#{action}.html", assigns)

      # Default implementations of Phoenix.LiveController callbacks

      def apply_session(socket, _session),
        do: socket

      def action_handler(socket, name, params),
        do: apply(__MODULE__, name, [socket, params])

      def event_handler(socket, name, params),
        do: apply(__MODULE__, name, [socket, params])

      def message_handler(socket, name, message),
        do: apply(__MODULE__, name, [socket, message])

      defoverridable apply_session: 2,
                     action_handler: 3,
                     event_handler: 3,
                     message_handler: 3,
                     render: 1
    end
  end

  defmacro __before_compile__(env) do
    build_handler_before(env.module) ++
      [
        quote do
          Module.delete_attribute(__MODULE__, :action_handler)
          Module.delete_attribute(__MODULE__, :event_handler)
          Module.delete_attribute(__MODULE__, :message_handler)

          @doc false
          def __live_controller__(:actions), do: @actions
          def __live_controller__(:events), do: @events
          def __live_controller__(:messages), do: @messages

          def handle_info(message, socket),
            do:
              unquote(__MODULE__)._handle_message(
                __MODULE__,
                &__live_controller_before__/3,
                message,
                socket
              )

          defp __live_controller_before__(_socket, name, _payload),
            do: raise("Unknown live controller handler: #{inspect(name)}")
        end
      ]
  end

  defp build_handler_before(module) do
    handlers =
      (Module.get_attribute(module, :actions) |> Enum.map(&{&1, :action})) ++
        (Module.get_attribute(module, :events) |> Enum.map(&{&1, :event})) ++
        (Module.get_attribute(module, :messages) |> Enum.map(&{&1, :message}))

    plugs = Module.get_attribute(module, :plugs)

    Enum.map(handlers, fn {name, type} ->
      quote do
        defp __live_controller_before__(socket, unquote(name), payload) do
          unquote(build_handler_plug_calls(name, type, plugs))
        end
      end
    end)
  end

  defp build_handler_plug_calls(_, _, []) do
    quote do
      socket
    end
  end

  defp build_handler_plug_calls(name, type, plugs) do
    plugs
    |> Enum.map(fn {caller, args, conditions, target_mod, target_fun} ->
      call = if args do
        args = Enum.map(args, &prepare_plug_expression_ast(&1, caller))
        quote(do: unquote(target_fun)(unquote_splicing(args)))
      else
        args = quote(do: [socket])
        if target_mod,
          do: quote(do: unquote(target_mod).unquote(target_fun)(unquote_splicing(args))),
          else: quote(do: unquote(target_fun)(unquote_splicing(args)))
      end

      quote do
        chain(socket, fn socket ->
          unquote(build_plug_ast_vars(type, name))

          if unquote(prepare_plug_expression_ast(conditions, caller)) do
            unquote(call)
          else
            socket
          end
        end)
      end
    end)
    |> Enum.reverse()
    |> Enum.reduce(fn
      {{:., [], target}, [], [_socket | rem_args]}, last_socket ->
        {{:., [], target}, [], [last_socket | rem_args]}

      {name, [], [_socket | rem_args]}, last_socket ->
        {name, [], [last_socket | rem_args]}
    end)
  end

  defp build_plug_ast_vars(type, name) do
    with_params = type in [:action, :event]
    with_payload = type == :message
    action = if type == :action, do: name
    event = if type == :event, do: name
    message = if type == :message, do: name

    quote do
      var!(socket) = socket

      var!(params) = if unquote(with_params), do: payload
      var!(payload) = if unquote(with_payload), do: payload
      var!(action) = payload && unquote(action)
      var!(event) = payload && unquote(event)
      var!(message) = payload && unquote(message)

      var!(socket)
      var!(params)
      var!(payload)
      var!(action)
      var!(event)
      var!(message)
    end
  end

  defp prepare_plug_expression_ast(ast, caller) do
    ast
    |> remove_ast_vars_context([:params, :payload, :action, :event, :message, :socket])
    |> Macro.expand(caller)
  end

  defp remove_ast_vars_context(ast, vars) do
    ast
    |> Macro.prewalk(nil, fn
      node = {var, meta, _}, nil ->
        if var in vars,
          do: {{var, Keyword.delete(meta, :counter), nil}, nil},
          else: {node, nil}

      node, nil ->
        {node, nil}
    end)
    |> elem(0)
  end

  def __on_definition__(env, _kind, name, _args, _guards, _body) do
    pull_handler_attribute(env.module, :action_handler, :actions, name)
    pull_handler_attribute(env.module, :event_handler, :events, name)
    pull_handler_attribute(env.module, :message_handler, :messages, name)
  end

  defp pull_handler_attribute(module, source_attr, target_attr, name) do
    with true <- Module.delete_attribute(module, source_attr),
         current_names = Module.get_attribute(module, target_attr),
         false <- Enum.member?(current_names, name) do
      Module.put_attribute(module, target_attr, name)
    end
  end

  def _mount(module, before_callback, params, session, socket) do
    action =
      socket.assigns[:live_action] ||
        raise """
        #{inspect(module)} called without action.

        Make sure to mount it via route that specifies action, e.g. for :index action:

            live "/some_url", #{inspect(module)}, :index

        """

    unless Enum.member?(module.__live_controller__(:actions), action),
      do:
        raise("""
        #{inspect(module)} doesn't implement action handler for #{inspect(action)} action.

        Make sure that #{action} function is defined and annotated as action handler:

            @action_handler true
            def #{action}(socket, params) do
              # ...
            end

        """)

    socket
    |> Map.put_new(:mounted?, false)
    |> module.apply_session(session)
    |> before_callback.(action, params)
    |> chain(&module.action_handler(&1, action, params))
    |> wrap_socket(&{:ok, &1})
  end

  def _handle_params(module, before_callback, params, _url, socket) do
    action = socket.assigns.live_action

    unless Map.get(socket, :mounted?) do
      socket
      |> Map.put(:mounted?, true)
      |> wrap_socket(&{:noreply, &1})
    else
      socket
      |> before_callback.(action, params)
      |> chain(&module.action_handler(&1, action, params))
      |> wrap_socket(&{:noreply, &1})
    end
  end

  def _handle_event(module, before_callback, event_string, params, socket) do
    unless Enum.any?(module.__live_controller__(:events), &(to_string(&1) == event_string)),
      do:
        raise("""
        #{inspect(module)} doesn't implement event handler for #{inspect(event_string)} event.

        Make sure that #{event_string} function is defined and annotated as event handler:

            @event_handler true
            def #{event_string}(socket, params) do
              # ...
            end

        """)

    event = String.to_atom(event_string)

    socket
    |> before_callback.(event, params)
    |> chain(&module.event_handler(&1, event, params))
    |> wrap_socket(&{:noreply, &1})
  end

  def _handle_message(module, before_callback, message_payload, socket) do
    message_key =
      cond do
        is_atom(message_payload) ->
          message_payload

        is_tuple(message_payload) and is_atom(elem(message_payload, 0)) ->
          elem(message_payload, 0)

        true ->
          nil
      end

    unless message_key,
      do:
        raise("""
        Message #{inspect(message_payload)} cannot be handled by message handler and
        #{inspect(module)} doesn't implement handle_info/3 that would handle it instead.

        Make sure that appropriate handle_info/3 function matching this message is defined:

            def handle_info(message, socket) do
              # ...
            end

        """)

    unless Enum.member?(module.__live_controller__(:messages), message_key),
      do:
        raise("""
        #{inspect(module)} doesn't implement message handler for #{inspect(message_payload)} message.

        Make sure that #{message_key} function is defined and annotated as message handler:

            @message_handler true
            def #{message_key}(socket, message) do
              # ...
            end

        """)

    socket
    |> before_callback.(message_key, message_payload)
    |> chain(&module.message_handler(&1, message_key, message_payload))
    |> wrap_socket(&{:noreply, &1})
  end

  @doc ~S"""
  Calls given function if socket wasn't redirected, passes the socket through otherwise.

  Read more about the role that this function plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  @spec chain(
          socket ::
            Socket.t() | {:ok, Socket.t()} | {:ok, Socket.t(), keyword()} | {:noreply, Socket.t()},
          func :: function
        ) :: Socket.t()
  def chain(socket = %{redirected: nil}, func), do: func.(socket)
  def chain(halted_socket, _func), do: halted_socket

  @doc ~S"""
  Returns true if the socket was previously mounted by action handler.

  Read more about the role that this function plays when implementing action handlers in docs for
  `Phoenix.LiveController`.
  """
  @spec mounted?(socket :: Socket.t()) :: boolean()
  def mounted?(_socket = %{mounted?: true}), do: true
  def mounted?(_socket), do: false

  defp wrap_socket(socket = %Phoenix.LiveView.Socket{}, wrapper), do: wrapper.(socket)
  defp wrap_socket(misc, _wrapper), do: misc

  @doc """
  Define a callback that acts on a socket before action, event or essage handler.

  Read more about the role that this macro plays in the live controller pipeline in docs for
  `Phoenix.LiveController`.
  """
  defmacro plug(target) do
    {target, conditions} = extract_when(target)

    {target_mod, target_fun, args} =
      case target do
        atom when is_atom(atom) -> {nil, atom, nil}
        ast = {:__aliases__, _meta, _parts} -> {Macro.expand(ast, __CALLER__), :call, nil}
        {ast = {:__aliases__, _meta, _parts}, fun} -> {Macro.expand(ast, __CALLER__), fun, nil}
        {fun, _meta, args} -> {nil, fun, args}
      end

    plug = {__CALLER__, args, conditions, target_mod, target_fun}

    quote do
      @plugs unquote(Macro.escape(plug))
    end
  end

  defp extract_when({:when, _, [left, when_conditions]}), do: {left, when_conditions}
  defp extract_when(other), do: {other, true}
end
