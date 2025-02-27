#!/bin/bash

# Danh sách vùng AWS cần thay đổi instance
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# URL chứa User Data trên GitHub
user_data_url="https://raw.githubusercontent.com/kiemtien1/data/refs/heads/main/vixmr"

# Đường dẫn lưu User Data
user_data_file="/tmp/user_data.sh"

# Tải User Data từ GitHub
echo "📥 Đang tải user-data từ GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

# Kiểm tra xem tệp đã tải về có hợp lệ không
if [ ! -s "$user_data_file" ]; then
    echo "❌ Lỗi: Không thể tải user-data từ GitHub."
    exit 1
fi

# Mã hóa User Data thành base64
user_data_base64=$(base64 "$user_data_file" | tr -d '\n')

# Hàm cập nhật instance type mới
get_new_instance_type() {
    case "$1" in
        "c7a.large") echo "c7a.2xlarge" ;;
        *) echo "c7a.2xlarge" ;; # Mặc định nếu không xác định được
    esac
}

# Lặp qua từng vùng để dừng và thay đổi instance type
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
    for INSTANCE in $INSTANCE_IDS; do
        aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE" --no-cli-pager
    done
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

    # Thay đổi instance type và cập nhật user-data
    for INSTANCE in $INSTANCE_IDS; do
        CURRENT_TYPE=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --region "$REGION" \
            --query "Reservations[*].Instances[*].InstanceType" --output text)
        NEW_TYPE=$(get_new_instance_type "$CURRENT_TYPE")

        if [ "$CURRENT_TYPE" == "$NEW_TYPE" ]; then
            echo "✅ Instance $INSTANCE đã có type $NEW_TYPE, bỏ qua thay đổi."
        else
            echo "🔄 Đổi instance $INSTANCE từ $CURRENT_TYPE ➝ $NEW_TYPE"
            aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
                --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region "$REGION" --no-cli-pager
        fi

        # Cập nhật User Data
        echo "🔄 Cập nhật User Data cho instance $INSTANCE..."
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
            --attribute userData \
            --value "$user_data_base64" \
            --region "$REGION"

        # Đánh dấu đã cập nhật User Data
        aws ec2 create-tags --resources "$INSTANCE" --tags Key=UserDataUpdated,Value=true --region "$REGION"

        # Khởi động lại instance để áp dụng User Data
        aws ec2 reboot-instances --instance-ids "$INSTANCE" --region "$REGION"
    done

    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    for INSTANCE in $INSTANCE_IDS; do
        aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE" --no-cli-pager
    done
done

echo "✅ Hoàn tất thay đổi instance type và cập nhật User Data!"
