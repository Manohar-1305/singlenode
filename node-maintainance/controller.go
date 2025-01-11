package main

import (
    "context"
    "fmt"
    "time"

    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/util/retry"
    "k8s.io/klog/v2"
)

type Controller struct {
    kubeClient kubernetes.Interface
}

func (c *Controller) Run(stopCh <-chan struct{}) error {
    // Start the informer factories to begin populating the informer caches
    klog.Info("Starting NodeMaintenance controller")
    
    // Start workers
    go c.worker()
    
    <-stopCh
    klog.Info("Shutting down NodeMaintenance controller")
    return nil
}

func (c *Controller) worker() {
    for c.processNextWorkItem() {
    }
}

func (c *Controller) processNextWorkItem() bool {
    // Get the next maintenance request
    maintenance, err := c.getNextMaintenance()
    if err != nil {
        klog.Errorf("Error getting next maintenance: %v", err)
        return true
    }

    if maintenance == nil {
        // No maintenance to process, wait and retry
        time.Sleep(10 * time.Second)
        return true
    }

    // Process the maintenance
    if err := c.processMaintenance(maintenance); err != nil {
        klog.Errorf("Error processing maintenance: %v", err)
        c.updateMaintenanceStatus(maintenance, "Failed", err.Error())
        return true
    }

    return true
}

func (c *Controller) processMaintenance(maintenance *NodeMaintenance) error {
    // Update status to InProgress
    if err := c.updateMaintenanceStatus(maintenance, "InProgress", "Starting maintenance"); err != nil {
        return err
    }

    // If drain is enabled, drain the node
    if maintenance.Spec.Drain {
        if err := c.drainNode(maintenance.Spec.NodeName); err != nil {
            return fmt.Errorf("failed to drain node: %v", err)
        }
    }

    // Cordon the node
    if err := c.cordonNode(maintenance.Spec.NodeName); err != nil {
        return fmt.Errorf("failed to cordon node: %v", err)
    }

    // Wait for the maintenance duration
    if maintenance.Spec.Duration != "" {
        duration, err := time.ParseDuration(maintenance.Spec.Duration)
        if err != nil {
            return fmt.Errorf("invalid duration format: %v", err)
        }
        time.Sleep(duration)
    }

    // Uncordon the node
    if err := c.uncordonNode(maintenance.Spec.NodeName); err != nil {
        return fmt.Errorf("failed to uncordon node: %v", err)
    }

    // Update status to Completed
    return c.updateMaintenanceStatus(maintenance, "Completed", "Maintenance completed successfully")
}

func (c *Controller) drainNode(nodeName string) error {
    // Get all pods on the node
    pods, err := c.kubeClient.CoreV1().Pods("").List(context.TODO(), metav1.ListOptions{
        FieldSelector: fmt.Sprintf("spec.nodeName=%s", nodeName),
    })
    if err != nil {
        return err
    }

    // Delete each pod
    for _, pod := range pods.Items {
        if pod.Namespace == "kube-system" {
            // Skip system pods
            continue
        }

        err := c.kubeClient.CoreV1().Pods(pod.Namespace).Delete(context.TODO(), pod.Name, metav1.DeleteOptions{})
        if err != nil {
            return err
        }
    }

    return nil
}

func (c *Controller) cordonNode(nodeName string) error {
    return retry.RetryOnConflict(retry.DefaultRetry, func() error {
        node, err := c.kubeClient.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
        if err != nil {
            return err
        }

        node.Spec.Unschedulable = true
        _, err = c.kubeClient.CoreV1().Nodes().Update(context.TODO(), node, metav1.UpdateOptions{})
        return err
    })
}

func (c *Controller) uncordonNode(nodeName string) error {
    return retry.RetryOnConflict(retry.DefaultRetry, func() error {
        node, err := c.kubeClient.CoreV1().Nodes().Get(context.TODO(), nodeName, metav1.GetOptions{})
        if err != nil {
            return err
        }

        node.Spec.Unschedulable = false
        _, err = c.kubeClient.CoreV1().Nodes().Update(context.TODO(), node, metav1.UpdateOptions{})
        return err
    })
}

func (c *Controller) updateMaintenanceStatus(maintenance *NodeMaintenance, phase, message string) error {
    // Implementation would depend on your client for the NodeMaintenance CRD
    // This is a placeholder for the status update logic
    return nil
}