#!/bin/bash

# S3事件通知配置脚本
# 用于配置S3桶的Lambda触发事件

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 显示帮助信息
show_help() {
    echo "S3事件通知配置脚本"
    echo ""
    echo "用法:"
    echo "  $0 [S3桶名] [Lambda函数名] [AWS区域]"
    echo ""
    echo "参数:"
    echo "  S3桶名        存储图片的S3桶名称 (必需)"
    echo "  Lambda函数名  Lambda函数名称 (必需)"
    echo "  AWS区域       AWS区域 (默认: us-west-2)"
    echo ""
    echo "示例:"
    echo "  $0 my-image-bucket image-to-webp"
    echo "  $0 my-image-bucket image-to-webp us-east-1"
}

# 获取参数
get_parameters() {
    if [ -z "$1" ]; then
        echo -n "请输入S3桶名: "
        read BUCKET_NAME
        if [ -z "$BUCKET_NAME" ]; then
            print_error "S3桶名不能为空"
            exit 1
        fi
    else
        BUCKET_NAME="$1"
    fi
    
    if [ -z "$2" ]; then
        echo -n "请输入Lambda函数名: "
        read FUNCTION_NAME
        if [ -z "$FUNCTION_NAME" ]; then
            print_error "Lambda函数名不能为空"
            exit 1
        fi
    else
        FUNCTION_NAME="$2"
    fi
    
    if [ -z "$3" ]; then
        AWS_REGION="us-west-2"
        print_info "使用默认区域: $AWS_REGION"
    else
        AWS_REGION="$3"
    fi
    
    # 获取账户ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
    
    print_info "配置参数:"
    echo "  S3桶名: $BUCKET_NAME"
    echo "  Lambda函数名: $FUNCTION_NAME"
    echo "  AWS区域: $AWS_REGION"
    echo "  Lambda ARN: $LAMBDA_ARN"
}

# 检查资源是否存在
check_resources() {
    print_info "检查资源..."
    
    # 检查S3桶
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        print_error "S3桶不存在: $BUCKET_NAME"
        exit 1
    fi
    print_success "S3桶存在: $BUCKET_NAME"
    
    # 检查Lambda函数
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_error "Lambda函数不存在: $FUNCTION_NAME"
        exit 1
    fi
    print_success "Lambda函数存在: $FUNCTION_NAME"
}

# 配置Lambda权限
configure_lambda_permissions() {
    print_info "配置Lambda权限..."
    
    # 给Lambda函数S3调用权限
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
        --statement-id s3-trigger-permission \
        --region "$AWS_REGION" 2>/dev/null || print_warning "权限可能已存在"
    
    print_success "Lambda权限配置完成"
}

# 清除现有事件通知
clear_existing_notifications() {
    print_info "清除现有S3事件通知..."
    
    # 清空事件通知配置
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration '{}' \
        --region "$AWS_REGION"
    
    # 等待配置生效
    sleep 2
    print_success "现有事件通知已清除"
}

# 配置S3事件通知
configure_s3_events() {
    print_info "配置S3事件通知..."
    
    # 创建S3事件通知配置文件
    cat > s3-notification-config.json << EOF
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "${FUNCTION_NAME}_png",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".png"
            }
          ]
        }
      }
    },
    {
      "Id": "${FUNCTION_NAME}_jpg",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".jpg"
            }
          ]
        }
      }
    },
    {
      "Id": "${FUNCTION_NAME}_jpeg",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".jpeg"
            }
          ]
        }
      }
    },
    {
      "Id": "${FUNCTION_NAME}_bmp",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".bmp"
            }
          ]
        }
      }
    },
    {
      "Id": "${FUNCTION_NAME}_tiff",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".tiff"
            }
          ]
        }
      }
    },
    {
      "Id": "${FUNCTION_NAME}_tif",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "Suffix",
              "Value": ".tif"
            }
          ]
        }
      }
    }
  ]
}
EOF

    # 应用S3事件通知配置
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration file://s3-notification-config.json \
        --region "$AWS_REGION"
    
    print_success "S3事件通知配置完成"
}

# 验证配置
verify_configuration() {
    print_info "验证配置..."
    
    # 获取当前配置
    aws s3api get-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" > current-config.json
    
    # 检查配置是否包含Lambda函数
    if grep -q "$FUNCTION_NAME" current-config.json; then
        print_success "S3事件通知配置验证成功"
        
        # 显示配置的事件类型
        echo ""
        print_info "配置的触发事件:"
        echo "  - PNG文件上传"
        echo "  - JPG文件上传"
        echo "  - JPEG文件上传"
        echo "  - BMP文件上传"
        echo "  - TIFF文件上传"
        echo "  - TIF文件上传"
    else
        print_error "S3事件通知配置验证失败"
        exit 1
    fi
}

# 测试配置
test_configuration() {
    print_info "测试配置..."
    
    # 创建测试文件
    echo "Test image trigger" > test-trigger.png
    
    print_info "上传测试文件..."
    aws s3 cp test-trigger.png "s3://${BUCKET_NAME}/test-trigger.png" --region "$AWS_REGION"
    
    print_info "等待Lambda执行..."
    sleep 5
    
    # 检查是否有日志组创建
    if aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${FUNCTION_NAME}" \
        --region "$AWS_REGION" | grep -q "logGroupName"; then
        print_success "Lambda函数已被触发！"
        print_info "查看日志: aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
    else
        print_warning "未检测到Lambda执行，请检查配置或稍后再试"
    fi
    
    # 清理测试文件
    rm -f test-trigger.png
    aws s3 rm "s3://${BUCKET_NAME}/test-trigger.png" --region "$AWS_REGION" 2>/dev/null || true
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    rm -f s3-notification-config.json current-config.json
    print_success "清理完成"
}

# 显示结果
show_results() {
    echo ""
    print_success "🎉 S3事件通知配置完成！"
    echo ""
    echo "📋 配置信息:"
    echo "  S3桶: $BUCKET_NAME"
    echo "  Lambda函数: $FUNCTION_NAME"
    echo "  触发事件: s3:ObjectCreated:*"
    echo "  支持格式: .png, .jpg, .jpeg, .bmp, .tiff, .tif"
    echo ""
    echo "🧪 测试方法:"
    echo "  aws s3 cp image.png s3://${BUCKET_NAME}/"
    echo ""
    echo "📊 查看日志:"
    echo "  aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
    echo ""
    echo "🔧 修改配置:"
    echo "  重新运行此脚本即可更新配置"
}

# 主函数
main() {
    echo "⚙️  S3事件通知配置脚本"
    echo "=========================="
    
    # 检查帮助参数
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # 执行配置步骤
    get_parameters "$@"
    check_resources
    configure_lambda_permissions
    clear_existing_notifications
    configure_s3_events
    verify_configuration
    test_configuration
    cleanup
    show_results
}

# 错误处理
trap 'print_error "配置过程中发生错误"; cleanup; exit 1' ERR

# 运行主函数
main "$@"
