#!/bin/bash

# Danh sách vùng AWS cần thay đổi instance
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# URL chứa User Data trên GitHub
user_data_url="https://raw.githubusercontent.com/kiemtien1/data/refs/heads/main/vixmr"

# Đường dẫn đến file User Data
user_data_file="/tmp/user_data.sh"

# Tải User Data từ GitHub
echo "Downloading user-data from GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

# Kiểm tra xem file có tồn tại và không rỗng không
if [ ! -s "$user_data_file" ]; then
    echo "Error: Failed to download user-data from GitHub."
    exit 1
fi

# Mã hóa User Data sang base64 để sử dụng trong AWS
user_data_base64=$(base64 -w 0 "$user_data_file")

# Hàm để lấy instance type mới
get_new_instance_type() {
    case "$1" in
        "c7a.large") echo "c7a.2xlarge" ;;
        *) echo "c7a.2xlarge" ;; # Mặc định nếu không xác định được
    esac
}

# Lặp qua từng vùng để thay đổi instance type
for REGION in "${REGIONS[@]}"; do
    echo "🔹 Đang xử lý vùng: $REGION"

    # Lấy danh sách Instance ID trong vùng
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
        --query "Reservations[*].Instances[*].InstanceId" --output text)

    if [ -z "$INSTANCE_IDS" ]; then
        echo "⚠️ Không có instance nào trong vùng $REGION."
        continue
    fi

    echo "🛑 Dừng tất cả instances trong vùng $REGION..."
    echo "$INSTANCE_IDS" | xargs aws ec2 stop-instances --region "$REGION" --instance-ids --no-cli-pager
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

    # Thay đổi instance type và cập nhật User Data
    for INSTANCE in $INSTANCE_IDS; do
        CURRENT_TYPE=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --region "$REGION" \
            --query "Reservations[*].Instances[*].InstanceType" --output text)
        NEW_TYPE=$(get_new_instance_type "$CURRENT_TYPE")

        if [ "$CURRENT_TYPE" == "$NEW_TYPE" ]; then
            echo "✅ Instance $INSTANCE đã có type $NEW_TYPE, bỏ qua thay đổi."
            continue
        fi

        echo "🔄 Đổi instance $INSTANCE từ $CURRENT_TYPE ➝ $NEW_TYPE"
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
            --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region "$REGION" --no-cli-pager

        # Cập nhật User Data
        echo "🔄 Cập nhật user data cho instance $INSTANCE"
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
            --attribute userData \
            --value "{\"UserData\": \"$user_data_base64\"}" \
            --region "$REGION"

        # Reboot instance để áp dụng User Data mới
        echo "🔄 Rebooting instance $INSTANCE"
        aws ec2 reboot-instances --instance-ids "$INSTANCE" --region "$REGION"

        # Kiểm tra xem User Data có được áp dụng thành công không
        echo "🔄 Kiểm tra trạng thái User Data trên instance $INSTANCE"
        sleep 30 # Đợi một chút để instance khởi động lại
        INSTANCE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --region "$REGION" \
            --query "Reservations[*].Instances[*].PublicIpAddress" --output text)
        
        if [ -z "$INSTANCE_IP" ]; then
            echo "⚠️ Không thể lấy địa chỉ IP của instance $INSTANCE."
            continue
        fi

        echo "🔄 Kết nối đến instance $INSTANCE để kiểm tra User Data..."
        ssh -o StrictHostKeyChecking=no -i /path/to/your/key.pem ec2-user@$INSTANCE_IP "
            sudo cat /var/log/cloud-init-output.log
        "
    done

    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    echo "$INSTANCE_IDS" | xargs aws ec2 start-instances --region "$REGION" --instance-ids --no-cli-pager
done

echo "✅ Hoàn tất thay đổi instance type và cập nhật User Data cho tất cả vùng!"
