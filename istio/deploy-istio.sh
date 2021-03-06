#!/bin/sh

cd `dirname "$0"`
BASE_DIR=`pwd`

# 只支持结合Mycat、ZipKin一起部署到k8s，否则需要修改相关YAML配置文件。
# 例如如果不使用Mycat，则svc-user-deployment.yaml、svc-order-deployment.yaml中
# initContainers对mycat的监控需要去掉，否则无法启动
# 这里确保使用 -mycat -zipkin 参数建立Docker镜像
../package.sh -clean -mycat -zipkin
../docker/deploy-mydemo.sh -stop -rm -rmi -build

# YAML文件配置考虑了基本的服务依赖关系，若依赖项未就绪则一直等待，等待时间过长k8s会重新启动新的POD继续尝试。
# 但是单机资源有限，为了避免k8s不断重启POD，消耗额外的资源，因此下面脚本加入了一些监测点，等前面依赖项就绪后
# 再部署后续服务。

# =================================================================
# Start MySQL
kubectl apply -f deployment/mysql-statefulset.yaml
echo "> Wait MySQL POD to run ... "
STATUS=""
POD_NAME=""
while :
do
	POD_NAME=`kubectl get pods | grep db-demo | grep Running | awk '{print $1}'`
	if [ "$POD_NAME" != "" ]; then
		if [ "$STATUS" = "" ]; then
			echo "> MySQL POD is running: $POD_NAME, wait MySQL startup ... "
			STATUS="0"
		fi
		kubectl logs $POD_NAME -c db-demo > mysql.log
		COUNT=`grep 'ready for connections' mysql.log -c`
		if [[ "$COUNT" = "1" && "$STATUS" = "0" ]]; then
			echo "> MySQL is initializing ... "
			STATUS="1"
		fi
		if [ "$COUNT" = "2" ]; then
			echo "> MySQL initialized, is ready for connections"
			break
		fi
	fi
	sleep 2
done
rm -rf mysql.log
echo "> Wait MySQL to be READY"
while :
do
	COUNT=`kubectl get statefulset | grep db-demo | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> MySQL is READY now"
		break
	fi
	sleep 3
done

# =================================================================
# Start Mycat
kubectl create -f deployment/mycat-statefulset.yaml
echo "> Wait Mycat to be READY"
while :
do
	COUNT=`kubectl get statefulset | grep mycat-demo | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Mycat is READY now"
		break
	fi
	sleep 3
done

# =================================================================
# Start Nacos, ZipKin
kubectl create -f deployment/nacos-statefulset.yaml
kubectl create -f deployment/zipkin-statefulset.yaml
echo "> Wait Nacos to be READY"
while :
do
	COUNT=`kubectl get statefulset | grep pub-nacos | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Nacos is READY now"
		break
	fi
	sleep 3
done

# =================================================================
# Start item, stock, user services
kubectl create -f deployment/svc-item-deployment.yaml
kubectl create -f deployment/svc-stock-deployment.yaml
kubectl create -f deployment/svc-user-deployment.yaml
echo "> Wait Stock service to be READY"
while :
do
	COUNT=`kubectl get deployment | grep svc-stock | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Stock service is READY now"
		break
	fi
	sleep 3
done
echo "> Wait Item service to be READY"
while :
do
	COUNT=`kubectl get deployment | grep svc-item | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Item service is READY now"
		break
	fi
	sleep 3
done

# =================================================================
# Start Order service
kubectl create -f deployment/svc-order-deployment.yaml
echo "> Wait Order Service to be READY"
while :
do
	COUNT=`kubectl get deployment | grep svc-order | grep '1/1' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Order Service is READY now"
		break
	fi
	sleep 3
done

kubectl create -f deployment/web-shop-deployment.yaml
echo "> Wait Shop Web to be READY"
while :
do
	COUNT=`kubectl get deployment | grep web-shop-v1 | grep '2/2' -c`
	if [ "$COUNT" = "1" ]; then
		echo "> Shop Web is READY now"
		break
	fi
	sleep 3
done
