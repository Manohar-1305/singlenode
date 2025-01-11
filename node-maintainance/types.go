package main

type NodeMaintenance struct {
    Spec   NodeMaintenanceSpec   `json:"spec"`
    Status NodeMaintenanceStatus `json:"status"`
}

type NodeMaintenanceSpec struct {
    NodeName  string `json:"nodeName"`
    Reason    string `json:"reason"`
    StartTime string `json:"startTime,omitempty"`
    Duration  string `json:"duration,omitempty"`
    Drain     bool   `json:"drain,omitempty"`
}

type NodeMaintenanceStatus struct {
    Phase          string `json:"phase"`
    LastUpdateTime string `json:"lastUpdateTime,omitempty"`
    Message        string `json:"message,omitempty"`
}