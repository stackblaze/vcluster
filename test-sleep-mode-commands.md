# Testing Sleep Mode with PostgreSQL vCluster

## Cluster Status

**Cluster Name**: `test-sleep`  
**Namespace**: `test-sleep`  
**Database**: PostgreSQL (auto-provisioned via connector)  
**Sleep Mode**: Enabled (5 minutes inactivity)

## Quick Commands

### Check Cluster Status
```bash
vcluster list -n test-sleep
kubectl get pods -n test-sleep
```

### Check Last Activity Timestamp
```bash
kubectl get statefulset -n test-sleep test-sleep -o jsonpath='{.metadata.annotations.vcluster\.loft\.sh/last-activity}' && echo
```

### Connect to vCluster
```bash
vcluster connect test-sleep -n test-sleep
# Then in another terminal, use kubectl commands
kubectl get pods
kubectl get nodes
```

### Test Sleep Mode

1. **Connect and make API calls** (this updates the activity timestamp):
   ```bash
   vcluster connect test-sleep -n test-sleep
   # In another terminal:
   kubectl get pods
   kubectl get nodes
   ```

2. **Disconnect and wait 5 minutes** (no API activity)

3. **Check if vCluster is paused**:
   ```bash
   vcluster list -n test-sleep
   # Should show status as "Paused" or "Sleeping"
   ```

4. **Check the controller logs** (to see sleep mode in action):
   ```bash
   kubectl logs -n test-sleep -l app=vcluster --tail=50 | grep -i sleep
   ```

5. **Manually resume** (if auto-sleep triggered):
   ```bash
   vcluster resume test-sleep -n test-sleep
   ```

### Monitor Sleep Mode Activity

Watch the activity annotation:
```bash
watch -n 10 'kubectl get statefulset -n test-sleep test-sleep -o jsonpath="{.metadata.annotations.vcluster\.loft\.sh/last-activity}" && echo " - $(date)"'
```

Check controller logs:
```bash
kubectl logs -n test-sleep -l app=vcluster -f | grep -i "sleep\|activity\|pause"
```

### Cleanup

Delete the test cluster:
```bash
vcluster delete test-sleep -n test-sleep
kubectl delete namespace test-sleep
```

## Expected Behavior

1. **Activity Tracking**: Every API request updates the `vcluster.loft.sh/last-activity` annotation
2. **Auto-Sleep**: After 5 minutes of inactivity, the controller will:
   - Scale down the vCluster StatefulSet/Deployment
   - Delete workload pods
   - Set paused annotations
3. **Manual Resume**: Use `vcluster resume` to wake it up

## Troubleshooting

If sleep mode doesn't trigger:
- Check controller logs: `kubectl logs -n test-sleep -l app=vcluster | grep sleep`
- Verify sleep mode is enabled: `kubectl get statefulset -n test-sleep test-sleep -o yaml | grep sleepMode`
- Check activity annotation exists: `kubectl get statefulset -n test-sleep test-sleep -o jsonpath='{.metadata.annotations}'`

