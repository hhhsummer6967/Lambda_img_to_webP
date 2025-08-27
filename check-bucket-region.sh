#!/bin/bash

# S3桶区域检测工具

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 显示帮助信息
show_help() {
    echo "S3桶区域检测工具"
    echo ""
    echo "用法:"
    echo "  $0 [S3桶名]"
    echo ""
    echo "示例:"
    echo "  $0 my-image-bucket"
}

# 检查S3桶区域
check_bucket_region() {
    local bucket_name="$1"
    
    if [ -z "$bucket_name" ]; then
        echo -n "请输入S3桶名: "
        read bucket_name
        if [ -z "$bucket_name" ]; then
            echo "❌ S3桶名不能为空"
            exit 1
        fi
    fi
    
    print_info "检查S3桶: $bucket_name"
    
    # 检查桶是否存在
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        echo "❌ S3桶不存在或无权限访问: $bucket_name"
        exit 1
    fi
    
    print_success "S3桶存在: $bucket_name"
    
    # 获取桶区域
    bucket_region=$(aws s3api get-bucket-location --bucket "$bucket_name" --query 'LocationConstraint' --output text 2>/dev/null)
    
    # 处理us-east-1的特殊情况
    if [ "$bucket_region" == "None" ] || [ "$bucket_region" == "null" ] || [ -z "$bucket_region" ]; then
        bucket_region="us-east-1"
    fi
    
    print_success "S3桶区域: $bucket_region"
    
    # 获取当前AWS CLI默认区域
    current_region=$(aws configure get region 2>/dev/null || echo "未设置")
    print_info "当前AWS CLI默认区域: $current_region"
    
    # 检查是否匹配
    if [ "$current_region" != "$bucket_region" ] && [ "$current_region" != "未设置" ]; then
        print_warning "区域不匹配！"
        echo ""
        echo "建议的部署命令:"
        echo "  ./deploy.sh $bucket_name $bucket_region"
    else
        print_success "区域匹配，可以直接部署"
        echo ""
        echo "建议的部署命令:"
        echo "  ./deploy.sh $bucket_name"
    fi
    
    echo ""
    echo "📋 区域信息总结:"
    echo "  S3桶名: $bucket_name"
    echo "  S3桶区域: $bucket_region"
    echo "  AWS CLI默认区域: $current_region"
    echo ""
    echo "💡 提示:"
    echo "  - Lambda函数必须与S3桶在同一区域"
    echo "  - 如果区域不匹配，请在部署时指定正确的区域"
    echo "  - 可以使用 'aws configure set region $bucket_region' 更新默认区域"
}

# 主函数
main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    echo "🔍 S3桶区域检测工具"
    echo "==================="
    echo ""
    
    check_bucket_region "$1"
}

# 运行主函数
main "$@"
