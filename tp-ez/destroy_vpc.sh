#!/bin/bash
# Script de suppression complète d'un VPC
# Usage: ./destroy_vpc.sh <VPC_ID>
# Appelé par le Job Jenkins après sélection via Active Choice

set -e

VPC_ID=$1
REGION=${AWS_DEFAULT_REGION:-us-east-1}

if [ -z "$VPC_ID" ]; then
  echo "Erreur : VPC_ID manquant"
  exit 1
fi

echo "============================================"
echo "Suppression complète du VPC : $VPC_ID"
echo "Région : $REGION"
echo "============================================"

# 1. Terminer les instances EC2
echo "[1/9] Terminaison des instances EC2..."
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,pending" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text --region $REGION)

if [ -n "$INSTANCES" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION
  echo "  Attente de la terminaison des instances..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCES --region $REGION
  echo "  Instances terminées : $INSTANCES"
else
  echo "  Aucune instance trouvée."
fi

# 2. Supprimer les NAT Gateways
echo "[2/9] Suppression des NAT Gateways..."
NAT_GWS=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
  --query "NatGateways[].NatGatewayId" \
  --output text --region $REGION)

if [ -n "$NAT_GWS" ]; then
  for NAT in $NAT_GWS; do
    aws ec2 delete-nat-gateway --nat-gateway-id $NAT --region $REGION
    echo "  NAT Gateway supprimée : $NAT"
  done
  echo "  Attente suppression NAT Gateways (60s)..."
  sleep 60
else
  echo "  Aucune NAT Gateway trouvée."
fi

# 3. Libérer les Elastic IPs associées
echo "[3/9] Libération des Elastic IPs..."
EIPS=$(aws ec2 describe-addresses \
  --filters "Name=domain,Values=vpc" \
  --query "Addresses[?AssociationId==null].AllocationId" \
  --output text --region $REGION)

if [ -n "$EIPS" ]; then
  for EIP in $EIPS; do
    aws ec2 release-address --allocation-id $EIP --region $REGION 2>/dev/null || true
    echo "  EIP libérée : $EIP"
  done
else
  echo "  Aucune EIP non associée trouvée."
fi

# 4. Détacher et supprimer l'Internet Gateway
echo "[4/9] Suppression de l'Internet Gateway..."
IGWS=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query "InternetGateways[].InternetGatewayId" \
  --output text --region $REGION)

if [ -n "$IGWS" ]; then
  for IGW in $IGWS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID --region $REGION
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $REGION
    echo "  IGW supprimée : $IGW"
  done
else
  echo "  Aucune IGW trouvée."
fi

# 5. Supprimer les sous-réseaux
echo "[5/9] Suppression des sous-réseaux..."
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[].SubnetId" \
  --output text --region $REGION)

if [ -n "$SUBNETS" ]; then
  for SUBNET in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $SUBNET --region $REGION
    echo "  Subnet supprimé : $SUBNET"
  done
else
  echo "  Aucun subnet trouvé."
fi

# 6. Supprimer les tables de routage (hors table principale)
echo "[6/9] Suppression des tables de routage..."
ROUTE_TABLES=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
  --output text --region $REGION)

if [ -n "$ROUTE_TABLES" ]; then
  for RT in $ROUTE_TABLES; do
    aws ec2 delete-route-table --route-table-id $RT --region $REGION
    echo "  Route table supprimée : $RT"
  done
else
  echo "  Aucune route table personnalisée trouvée."
fi

# 7. Supprimer les Security Groups (hors default)
echo "[7/9] Suppression des Security Groups..."
SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text --region $REGION)

if [ -n "$SGS" ]; then
  for SG in $SGS; do
    aws ec2 delete-security-group --group-id $SG --region $REGION 2>/dev/null || true
    echo "  Security Group supprimé : $SG"
  done
else
  echo "  Aucun Security Group personnalisé trouvé."
fi

# 8. Supprimer les Key Pairs créées par Terraform
echo "[8/9] Suppression des Key Pairs..."
aws ec2 delete-key-pair --key-name "tp-ez-admin-key" --region $REGION 2>/dev/null || true
aws ec2 delete-key-pair --key-name "tp-ez-common-key" --region $REGION 2>/dev/null || true
echo "  Key pairs supprimées."

# 9. Supprimer le VPC
echo "[9/9] Suppression du VPC $VPC_ID..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION
echo ""
echo "============================================"
echo "VPC $VPC_ID supprimé avec succès !"
echo "============================================"
