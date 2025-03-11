import subprocess
import json
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
        return json.loads(result.stdout) 
    except Exception as e:
        print(f"Error executing script: {e}")
        return {
            "filename": "Error",
            "tool_version": "N/A",
            "platform": "N/A",
            "duration": "N/A",
            "start_time": "N/A"
        }

# Dash app
app = dash.Dash(__name__)

# Layout
app.layout = html.Div(children=[
    html.H1("System Health Dashboard", style={"textAlign": "center"}),
    html.Div(id="system-info", style={
        "background-color": "#333", "color": "white",
        "padding": "15px", "border-radius": "5px",
        "width": "25%","marginLeft": "0px", "font-size": "18px"
    }),
    dcc.Interval(id="interval-component", n_intervals=0)
])

# Callback to update system info
@app.callback(Output("system-info", "children"), Input("interval-component", "n_intervals"))
def update_info(_):
    data = get_system_report()
    return html.Div([
        html.P(f"Filename: {data['filename']}"),
        html.P(f"Tool Version: {data['tool_version']}"),
        html.P(f"Platform: {data['platform']}"),
        html.P(f"Duration: {data['duration']} seconds"),
        html.P(f"Start Time: {data['start_time']}")
    ])

# Run the Server
if __name__ == '__main__':
    app.run_server(host="0.0.0.0", port=8080, debug=False)
