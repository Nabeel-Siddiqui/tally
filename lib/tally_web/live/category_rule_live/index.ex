defmodule TallyWeb.CategoryRuleLive.Index do
  use TallyWeb, :live_view

  alias Tally.Finance
  alias Tally.Finance.CategoryRule

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :category_rules, Finance.list_category_rules(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Category rules") |> assign(:category_rule, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:page_title, "New Category Rule") |> assign(:category_rule, %CategoryRule{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Category rules
      <:subtitle>Standing instructions applied to every future import.</:subtitle>
      <:actions>
        <.link patch={~p"/rules/new"}>
          <.button>New rule</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="category-rules" rows={@category_rules}>
      <:col :let={rule} label="Merchant contains">{rule.match_text}</:col>
      <:col :let={rule} label="Category">{rule.category}</:col>
    </.table>

    <p :if={@category_rules == []} class="mt-6 text-sm text-zinc-500">
      No rules yet — imported transactions will be uncategorized until you add one.
    </p>

    <.modal :if={@live_action == :new} id="category-rule-modal" show on_cancel={JS.patch(~p"/rules")}>
      <.live_component
        module={TallyWeb.CategoryRuleLive.FormComponent}
        id={:new}
        title={@page_title}
        action={@live_action}
        category_rule={@category_rule}
        current_user={@current_user}
        patch={~p"/rules"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({TallyWeb.CategoryRuleLive.FormComponent, {:saved, _rule}}, socket) do
    {:noreply,
     assign(socket, :category_rules, Finance.list_category_rules(socket.assigns.current_user))}
  end
end
