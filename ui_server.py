import subprocess
import json
import plotly.graph_objs as go
import dash
from dash import dcc, html
from dash.dependencies import Input, Output

START_TIME_FILE = "/tmp/health_check_start_time"
with open(START_TIME_FILE, "w") as f:
    f.write(str(subprocess.check_output("date +%s.%N", shell=True).decode().strip()))

# Function to execute Bash script and capture JSON output
def get_system_report():
    try:
        result = subprocess.run(
            ["./health_check_script.sh"],  
            capture_output=True, text=True, check=True
        )
        data = json.loads(result.stdout.strip())

        # Check if 'system' exists and is a dictionary
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
    dcc.Interval(id="interval-component", n_intervals=0)
])

@app.callback([Output("system-info", "children"), Output("ram-usage-pie", "figure"), Output("disk-usage-pie", "figure")], Input("interval-component", "n_intervals"))
def update_info(_):
    data = get_system_report()
    system_data = data.get("system", {})

    ram_usage = float(system_data.get("ram_usage_percent", 0))
    ram_free = 100 - ram_usage

    disk_usage = float(system_data.get("disk_usage_percent", 0))
    disk_free = 100 - disk_usage

    system_info = html.Div([
        html.P(f"Filename: {data.get('filename', 'N/A')}"),
        html.P(f"Tool Version: {data.get('tool_version', 'N/A')}"),
        html.P(f"Platform: {data.get('platform', 'N/A')}"),
        html.P(f"Duration: {data.get('duration', 'N/A')} seconds"),
        html.P(f"Start Time: {data.get('start_time', 'N/A')}")
    ])

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

    return system_info, ram_fig, disk_fig

# Run the Server
if __name__ == '__main__':
    app.run_server(host="0.0.0.0", port=8080, debug=False)
