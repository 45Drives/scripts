// This script is for "Print" function and it connects to ui_server.py
window.dash_clientside = Object.assign({}, window.dash_clientside, {
    print: {
        printPage: function(n_clicks) {
            if (n_clicks > 0) {
                window.print(); 
            }
            return null;
        }
    }
});
