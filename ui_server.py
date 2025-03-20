import subprocess
import json
import plotly.graph_objs as go
import dash
from dash import dcc, html, ClientsideFunction
from dash.dependencies import Input, Output
from dash_iconify import DashIconify

START_TIME_FILE = "/tmp/health_check_start_time"
with open(START_TIME_FILE, "w") as f:
    f.write(str(subprocess.check_output("date +%s.%N", shell=True).decode().strip()))

def get_system_report():
    try:
        result = subprocess.run(
            ["./health_check_script.sh"],  
            capture_output=True, text=True, check=True
        )
        data = json.loads(result.stdout.strip())

        if not isinstance(data.get("system"), dict):
            data["system"] = {}
        return data

    except json.JSONDecodeError as e:
        print(f"JSON parsing error: {e}")
        return {"system": {}}

    except Exception as e:
        print(f"Error executing script: {e}")
        return {"system": {}}

app = dash.Dash(__name__)

# Layout
app.layout = html.Div(children=[
    html.H1("System Health Dashboard", style={"textAlign": "center"}),
    html.Button("Export", id="export-btn", n_clicks=0, style={
        "backgroundColor": "#007BFF", "color": "white", "border": "none", "padding": "10px 20px", "borderRadius": "5px", "cursor": "pointer", "fontSize": "16px", "marginBottom": "20px", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    }),
    html.Button("Print", id="print-btn", n_clicks=0, style={
        "backgroundColor": "#007BFF", "color": "white", "border": "none", "marginLeft": "10px", "padding": "10px 20px", "borderRadius": "5px", "cursor": "pointer", "fontSize": "16px", "marginBottom": "20px", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    }),
    dcc.Download(id="download-system-report"),
    html.Div([
        # System Info Container
        html.Div(id="system-info", style={
            "background-color": "#333", "color": "white", "padding": "15px", "border-radius": "5px", "width": "28%", "font-size": "18px",  "marginTop": "100px", "marginRight": "20px", "display": "flex", "flexDirection": "column", "alignItems": "flex-start" 
        }),

        # Pie Charts Container
        html.Div([
            dcc.Graph(id="disk-usage-pie", style={"width": "48%", "display": "inline-block"}),
            dcc.Graph(id="ram-usage-pie", style={"width": "48%", "display": "inline-block"})
        ], style={"display": "flex", "justifyContent": "space-between", "width": "75%"})
    ], style={"display": "flex", "alignItems": "flex-start"}),

    html.Div([
        html.Div(id="cpu-info", style={
           "background-color": "#333", "color": "white", "padding": "15px", "border-radius": "5px", "width": "13%", "font-size": "18px", "marginTop": "90px", "marginRight": "20px", "display": "flex", "flexDirection": "column", "alignItems": "flex-start"  
        }),

        dcc.Graph(id="cpu-cores-threads-pie", style={"width": "30%", "display": "inline-block"})
    ], style={"display": "flex", "alignItems": "flex-start", "justifyContent": "center"}),

    html.Div([
        html.Div(id="checks-summary", style={"justifyContent": "space-between", "marginTop": "20px", "width": "100%"}),
    ], style={"display": "flex", "flexDirection": "column", "alignItems": "flex-start"}),

    html.Div([
        dcc.Graph(id="total-checks-pie", style={"width": "45%", "display": "inline-block"}),
    ], style={"display": "flex", "justifyContent": "space-between", "width": "75%"}),

    dcc.Interval(id="interval-component", interval=5000, n_intervals=0, max_intervals=-1)
])

@app.callback([Output("system-info", "children"), Output("cpu-info", "children"), Output("ram-usage-pie", "figure"), Output("disk-usage-pie", "figure"), 
               Output("cpu-cores-threads-pie", "figure"), Output("checks-summary", "children") ], Output("total-checks-pie", "figure"), Input("interval-component", "n_intervals"), prevent_initial_call=False)
def update_info(_):
    data = get_system_report()
    system_data = data.get("system", {})
    status_data = data.get("status", {})

    disk_usage = float(system_data.get("disk_usage_percent", 0))
    disk_free = 100 - disk_usage
    ram_usage = float(system_data.get("ram_usage_percent", 0))
    ram_free = 100 - ram_usage

    total_cores = system_data.get("total_cores", "N/A")
    total_threads = system_data.get("total_threads", "N/A")
    threads_in_use = system_data.get("threads_in_use", "N/A")
    threads_free = system_data.get("threads_free", "N/A")
    cores_in_use = system_data.get("cores_in_use", "N/A")
    cores_free = system_data.get("cores_free", "N/A")

    system_info = html.Div([
        html.P(f"Filename: {data.get('filename', 'N/A')}"),
        html.P(f"Tool Version: {data.get('tool_version', 'N/A')}"),
        html.P(f"Platform: {data.get('platform', 'N/A')}"),
        html.P(f"Duration: {data.get('duration', 'N/A')} seconds"),
        html.P(f"Start Time: {data.get('start_time', 'N/A')}")
    ])

    cpu_info = html.Div([
        html.P(f"Total Cores: {total_cores}"),
        html.P(f"Total Threads: {total_threads}"),
        html.P(f"Threads in Use: {threads_in_use}"),
        html.P(f"Threads Available: {threads_free}"),
        html.P(f"Cores in Use: {cores_in_use}"),
        html.P(f"Cores Free: {cores_free}")
    ])

    # Storage Usage Pie Chart
    disk_fig = go.Figure(data=[go.Pie(
        labels=["In Use", "Free"],
        values=[disk_usage, disk_free],
        marker=dict(colors=["#FF0000", "#00FF00"]),  # Red for used, Green for free
        textinfo="percent", 
        hoverinfo="label+percent" 
    )])
    disk_fig.update_layout(title="Storage Usage")

    # RAM Usage Pie Chart
    ram_fig = go.Figure(data=[go.Pie(
        labels=["In Use", "Free"],
        values=[ram_usage, ram_free],
        marker=dict(colors=["#FF0000", "#00FF00"]),  # Red for used, Green for free
        textinfo="percent",  
        hoverinfo="label+percent"
    )])
    ram_fig.update_layout(title="RAM Usage")

    # Cores vs Threads Pie Chart
    cpu_fig = go.Figure(data=[go.Pie(
        labels=["Cores", "Threads"],
        values=[total_cores, total_threads], 
        marker=dict(colors=["#FF0000", "#0000FF"]),  # Red for cores, Blue for threads
        textinfo="value",  
        hoverinfo="label+value",
    )])
    cpu_fig.update_layout(title="Cores vs Threads")

    total_checks = status_data.get("total_checks", 0)
    passed = status_data.get("passed", 0)
    failed = status_data.get("failed", 0)
    not_applicable = status_data.get("not_applicable", 0)
    not_reviewed = status_data.get("not_reviewed", 0)

    passed_card = html.Div([
        html.Div([
            DashIconify(icon="heroicons-solid:check-circle", width=24, style={"marginRight": "8px"}),
            html.Span(f"Passed: {passed}", style={"fontSize": "20px", "fontWeight": "bold"})
        ], style={"display": "flex", "alignItems": "center"})
    ], style={
        "background-color": "#28a745", "color": "white", "padding": "20px", "border-radius": "8px", "width": "22%", "display": "flex", "justifyContent": "center", "alignItems": "center", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    })

    failed_card = html.Div([
        html.Div([
            DashIconify(icon="heroicons-solid:x-circle", width=24, color="white", style={"marginRight": "8px"}),
            html.Span(f"Failed: {failed}", style={"fontSize": "20px", "fontWeight": "bold"})
        ], style={"display": "flex", "alignItems": "center"})
    ], style={
        "background-color": "#dc3545", "color": "white", "padding": "20px", "border-radius": "8px", "width": "22%", "display": "flex", "justifyContent": "center", "alignItems": "center", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    })

    not_applicable_card = html.Div([
        html.Div([
            DashIconify(icon="heroicons-solid:minus-circle", width=24, color="white", style={"marginRight": "8px"}),
            html.Span(f"Not Applicable: {not_applicable}", style={"fontSize": "20px", "fontWeight": "bold"})
        ], style={"display": "flex", "alignItems": "center"})
    ], style={
        "background-color": "#007bff", "color": "white", "padding": "20px", "border-radius": "8px", "width": "22%", "display": "flex", "justifyContent": "center", "alignItems": "center", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    })

    not_reviewed_card = html.Div([
        html.Div([
            DashIconify(icon="heroicons-solid:exclamation-circle", width=24, color="white", style={"marginRight": "8px"}),
            html.Span(f"Not Reviewed: {not_reviewed}", style={"fontSize": "20px", "fontWeight": "bold"})
        ], style={"display": "flex", "alignItems": "center"})
    ], style={
        "background-color": "#ffc107", "color": "white", "padding": "20px", "border-radius": "8px", "width": "22%", "display": "flex", "justifyContent": "center", "alignItems": "center", "boxShadow": "2px 2px 5px rgba(0, 0, 0, 0.2)"
    })

    checks_summary = html.Div([
        passed_card, failed_card, not_applicable_card, not_reviewed_card
    ], style={"display": "flex", "justifyContent": "space-between", "width": "100%"})

    passed = status_data.get("passed", 0)
    failed = status_data.get("failed", 0)
    not_applicable = status_data.get("not_applicable", 0)
    not_reviewed = status_data.get("not_reviewed", 0)
    total_checks = status_data.get("total_checks", 0)

    pie_fig = go.Figure(data=[
        go.Pie(
            labels=["Passed", "Failed", "Not Applicable", "Not Reviewed"],
            values=[passed, failed, not_applicable, not_reviewed],
            hole=0.6,
            marker=dict(colors=["#28a745", "#dc3545", "#007bff", "#ffc107"]),
            textinfo="value",
            hoverinfo="label+value",
        )
    ])

    pie_fig.update_layout(
        title="Status Count",
        annotations=[dict(text=f"Total: {total_checks}", x=0.5, y=0.5, font_size=20, showarrow=False)]
    )

    return system_info, cpu_info ,ram_fig, disk_fig, cpu_fig, checks_summary, pie_fig

# Export button
@app.callback(Output("download-system-report", "data"), Input("export-btn", "n_clicks"),prevent_initial_call=True)
def export_report(n_clicks):
    if n_clicks > 0:
        data = get_system_report()
        export_filename = data.get("filename", "system_report.json")  # Use dynamic filename
        return dict(content=json.dumps(data, indent=4), filename=export_filename)

app.clientside_callback(
    ClientsideFunction(namespace="print", function_name="printPage"),
    Input("print-btn", "n_clicks")
)

# Run the Server
if __name__ == '__main__':
    app.run_server(host="0.0.0.0", port=7070, debug=False)
