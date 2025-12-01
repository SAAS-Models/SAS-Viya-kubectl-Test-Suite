"""
kubectl client wrapper for Python tests
"""

import subprocess
import json
import yaml
from typing import Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)


class KubectlClient:
    """Wrapper for kubectl commands"""
    
    def __init__(self, namespace: str = "sas-viya", context: Optional[str] = None):
        self.namespace = namespace
        self.context = context
        self.kubectl_cmd = ["kubectl"]
        
        if context:
            self.kubectl_cmd.extend(["--context", context])
    
    def execute(self, args: List[str], json_output: bool = False) -> Tuple[bool, str, str]:
        """Execute kubectl command"""
        cmd = self.kubectl_cmd + args
        
        if json_output:
            cmd.extend(["-o", "json"])
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            success = result.returncode == 0
            return success, result.stdout, result.stderr
            
        except subprocess.TimeoutExpired:
            logger.error(f"Command timed out: {' '.join(cmd)}")
            return False, "", "Command timed out"
        except Exception as e:
            logger.error(f"Command failed: {e}")
            return False, "", str(e)
    
    def get_pods(self, label_selector: Optional[str] = None) -> List[Dict]:
        """Get pods in namespace"""
        args = ["get", "pods", "-n", self.namespace]
        
        if label_selector:
            args.extend(["-l", label_selector])
        
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_deployments(self) -> List[Dict]:
        """Get deployments in namespace"""
        args = ["get", "deployments", "-n", self.namespace]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_services(self) -> List[Dict]:
        """Get services in namespace"""
        args = ["get", "services", "-n", self.namespace]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_statefulsets(self) -> List[Dict]:
        """Get statefulsets in namespace"""
        args = ["get", "statefulsets", "-n", self.namespace]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_pvcs(self) -> List[Dict]:
        """Get PVCs in namespace"""
        args = ["get", "pvc", "-n", self.namespace]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_events(self, field_selector: Optional[str] = None) -> List[Dict]:
        """Get events in namespace"""
        args = ["get", "events", "-n", self.namespace]
        
        if field_selector:
            args.extend(["--field-selector", field_selector])
        
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_logs(self, pod_name: str, container: Optional[str] = None, 
                 tail: int = 100) -> str:
        """Get pod logs"""
        args = ["logs", pod_name, "-n", self.namespace, f"--tail={tail}"]
        
        if container:
            args.extend(["-c", container])
        
        success, stdout, _ = self.execute(args)
        return stdout if success else ""
    
    def describe(self, resource_type: str, resource_name: str) -> str:
        """Describe a resource"""
        args = ["describe", resource_type, resource_name, "-n", self.namespace]
        success, stdout, _ = self.execute(args)
        return stdout if success else ""
    
    def wait_for_condition(self, resource: str, condition: str, 
                          timeout: int = 300) -> bool:
        """Wait for resource condition"""
        args = [
            "wait",
            resource,
            f"--for={condition}",
            "-n", self.namespace,
            f"--timeout={timeout}s"
        ]
        
        success, _, _ = self.execute(args)
        return success
    
    def top_nodes(self) -> List[Dict]:
        """Get node metrics"""
        args = ["top", "nodes", "--no-headers"]
        success, stdout, _ = self.execute(args)
        
        if success and stdout:
            nodes = []
            for line in stdout.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 5:
                    nodes.append({
                        'name': parts[0],
                        'cpu': parts[1],
                        'cpu_percent': parts[2],
                        'memory': parts[3],
                        'memory_percent': parts[4]
                    })
            return nodes
        return []
    
    def top_pods(self) -> List[Dict]:
        """Get pod metrics"""
        args = ["top", "pods", "-n", self.namespace, "--no-headers"]
        success, stdout, _ = self.execute(args)
        
        if success and stdout:
            pods = []
            for line in stdout.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3:
                    pods.append({
                        'name': parts[0],
                        'cpu': parts[1],
                        'memory': parts[2]
                    })
            return pods
        return []

    def exec_command(self, pod_name: str, command: List[str], 
                     container: Optional[str] = None) -> Tuple[bool, str]:
        """Execute command in pod"""
        args = ["exec", pod_name, "-n", self.namespace]
        
        if container:
            args.extend(["-c", container])
        
        args.append("--")
        args.extend(command)
        
        success, stdout, _ = self.execute(args)
        return success, stdout
    
    def get_ingress(self) -> List[Dict]:
        """Get ingress resources"""
        args = ["get", "ingress", "-n", self.namespace]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
    
    def get_nodes(self) -> List[Dict]:
        """Get cluster nodes"""
        args = ["get", "nodes"]
        success, stdout, _ = self.execute(args, json_output=True)
        
        if success and stdout:
            data = json.loads(stdout)
            return data.get("items", [])
        return []
