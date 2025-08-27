#!/bin/bash

# SNS通知配置脚本
# 为Lambda函数配置失败通知和CloudWatch告警

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
    echo "SNS通知配置脚本"
    echo ""
    echo "用法:"
    echo "  $0 [Lambda函数名] [邮箱地址] [AWS区域] [选项]"
    echo ""
    echo "参数:"
    echo "  Lambda函数名  Lambda函数名称 (默认: image-to-webp)"
    echo "  邮箱地址      接收通知的邮箱 (必需)"
    echo "  AWS区域       AWS区域 (默认: us-west-2)"
    echo ""
    echo "选项:"
    echo "  --sms PHONE   添加短信通知 (格式: +1234567890)"
    echo "  --no-alarm    不创建CloudWatch告警"
    echo ""
    echo "示例:"
    echo "  $0 image-to-webp admin@example.com"
    echo "  $0 my-function admin@example.com us-east-1 --sms +1234567890"
}

# 解析参数
parse_arguments() {
    FUNCTION_NAME="image-to-webp"
    EMAIL=""
    AWS_REGION="us-west-2"
    SMS_PHONE=""
    CREATE_ALARM=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sms)
                SMS_PHONE="$2"
                shift 2
                ;;
            --no-alarm)
                CREATE_ALARM=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                if [ -z "$FUNCTION_NAME" ] || [ "$FUNCTION_NAME" == "image-to-webp" ]; then
                    FUNCTION_NAME="$1"
                elif [ -z "$EMAIL" ]; then
                    EMAIL="$1"
                elif [ -z "$AWS_REGION" ] || [ "$AWS_REGION" == "us-west-2" ]; then
                    AWS_REGION="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 检查必需参数
    if [ -z "$EMAIL" ]; then
        echo -n "请输入接收通知的邮箱地址: "
        read EMAIL
        if [ -z "$EMAIL" ]; then
            print_error "邮箱地址不能为空"
            exit 1
        fi
    fi
    
    print_info "配置参数:"
    echo "  Lambda函数: $FUNCTION_NAME"
    echo "  邮箱地址: $EMAIL"
    echo "  AWS区域: $AWS_REGION"
    [ -n "$SMS_PHONE" ] && echo "  短信号码: $SMS_PHONE"
    echo "  创建告警: $CREATE_ALARM"
}

# 检查Lambda函数是否存在
check_lambda_function() {
    print_info "检查Lambda函数..."
    
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_error "Lambda函数不存在: $FUNCTION_NAME"
        exit 1
    fi
    
    print_success "Lambda函数存在: $FUNCTION_NAME"
}

# 创建SNS主题
create_sns_topic() {
    print_info "创建SNS主题..."
    
    TOPIC_NAME="lambda-${FUNCTION_NAME}-failures"
    
    # 检查主题是否已存在
    EXISTING_TOPIC=$(aws sns list-topics --region "$AWS_REGION" --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" --output text)
    
    if [ -n "$EXISTING_TOPIC" ]; then
        TOPIC_ARN="$EXISTING_TOPIC"
        print_warning "SNS主题已存在: $TOPIC_ARN"
    else
        TOPIC_ARN=$(aws sns create-topic \
            --name "$TOPIC_NAME" \
            --region "$AWS_REGION" \
            --query 'TopicArn' --output text)
        print_success "SNS主题创建成功: $TOPIC_ARN"
    fi
}

# 配置邮件订阅
setup_email_subscription() {
    print_info "配置邮件订阅..."
    
    # 检查是否已订阅
    EXISTING_SUB=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$TOPIC_ARN" \
        --region "$AWS_REGION" \
        --query "Subscriptions[?Endpoint=='$EMAIL' && Protocol=='email'].SubscriptionArn" --output text)
    
    if [ -n "$EXISTING_SUB" ] && [ "$EXISTING_SUB" != "None" ]; then
        print_warning "邮件订阅已存在: $EMAIL"
    else
        aws sns subscribe \
            --topic-arn "$TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL" \
            --region "$AWS_REGION" > /dev/null
        print_success "邮件订阅配置完成: $EMAIL"
        print_warning "请检查邮箱并确认订阅"
    fi
}

# 配置短信订阅
setup_sms_subscription() {
    if [ -z "$SMS_PHONE" ]; then
        return 0
    fi
    
    print_info "配置短信订阅..."
    
    # 检查是否已订阅
    EXISTING_SUB=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$TOPIC_ARN" \
        --region "$AWS_REGION" \
        --query "Subscriptions[?Endpoint=='$SMS_PHONE' && Protocol=='sms'].SubscriptionArn" --output text)
    
    if [ -n "$EXISTING_SUB" ] && [ "$EXISTING_SUB" != "None" ]; then
        print_warning "短信订阅已存在: $SMS_PHONE"
    else
        aws sns subscribe \
            --topic-arn "$TOPIC_ARN" \
            --protocol sms \
            --notification-endpoint "$SMS_PHONE" \
            --region "$AWS_REGION" > /dev/null
        print_success "短信订阅配置完成: $SMS_PHONE"
    fi
}

# 配置Lambda失败目标
setup_lambda_destination() {
    print_info "配置Lambda失败目标..."
    
    # 检查是否已配置
    EXISTING_CONFIG=$(aws lambda get-function-event-invoke-config \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if echo "$EXISTING_CONFIG" | grep -q "OnFailure"; then
        print_warning "Lambda失败目标已配置"
    else
        aws lambda put-function-event-invoke-config \
            --function-name "$FUNCTION_NAME" \
            --destination-config "{\"OnFailure\":{\"Destination\":\"$TOPIC_ARN\"}}" \
            --region "$AWS_REGION" > /dev/null
        print_success "Lambda失败目标配置完成"
    fi
}

# 创建CloudWatch告警
create_cloudwatch_alarms() {
    if [ "$CREATE_ALARM" != "true" ]; then
        return 0
    fi
    
    print_info "创建CloudWatch告警..."
    
    # 错误告警
    ERROR_ALARM_NAME="lambda-${FUNCTION_NAME}-errors"
    if aws cloudwatch describe-alarms --alarm-names "$ERROR_ALARM_NAME" --region "$AWS_REGION" | grep -q "AlarmName"; then
        print_warning "错误告警已存在: $ERROR_ALARM_NAME"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$ERROR_ALARM_NAME" \
            --alarm-description "Lambda函数 $FUNCTION_NAME 错误告警" \
            --metric-name Errors \
            --namespace AWS/Lambda \
            --statistic Sum \
            --period 300 \
            --threshold 1 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
            --evaluation-periods 1 \
            --alarm-actions "$TOPIC_ARN" \
            --region "$AWS_REGION"
        print_success "错误告警创建完成: $ERROR_ALARM_NAME"
    fi
    
    # 执行时间告警
    DURATION_ALARM_NAME="lambda-${FUNCTION_NAME}-duration"
    if aws cloudwatch describe-alarms --alarm-names "$DURATION_ALARM_NAME" --region "$AWS_REGION" | grep -q "AlarmName"; then
        print_warning "执行时间告警已存在: $DURATION_ALARM_NAME"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$DURATION_ALARM_NAME" \
            --alarm-description "Lambda函数 $FUNCTION_NAME 执行时间告警" \
            --metric-name Duration \
            --namespace AWS/Lambda \
            --statistic Average \
            --period 300 \
            --threshold 30000 \
            --comparison-operator GreaterThanThreshold \
            --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
            --evaluation-periods 2 \
            --alarm-actions "$TOPIC_ARN" \
            --region "$AWS_REGION"
        print_success "执行时间告警创建完成: $DURATION_ALARM_NAME"
    fi
}

# 测试通知配置
test_notification() {
    print_info "测试通知配置..."
    
    # 创建测试负载
    cat > test-payload.json << EOF
{
  "Records": [
    {
      "s3": {
        "bucket": {
          "name": "non-existent-test-bucket-12345"
        },
        "object": {
          "key": "test-image.png"
        }
      }
    }
  ]
}
EOF

    # 调用Lambda函数（预期失败）
    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload file://test-payload.json \
        --region "$AWS_REGION" \
        test-response.json > /dev/null 2>&1 || true
    
    # 清理测试文件
    rm -f test-payload.json test-response.json
    
    print_success "测试调用完成，如果配置正确，你应该会收到失败通知"
}

# 显示配置结果
show_results() {
    echo ""
    print_success "🎉 SNS通知配置完成！"
    echo ""
    echo "📋 配置信息:"
    echo "  Lambda函数: $FUNCTION_NAME"
    echo "  SNS主题: $TOPIC_ARN"
    echo "  邮件通知: $EMAIL"
    [ -n "$SMS_PHONE" ] && echo "  短信通知: $SMS_PHONE"
    echo "  CloudWatch告警: $CREATE_ALARM"
    echo ""
    echo "📧 下一步:"
    echo "  1. 检查邮箱并确认SNS订阅"
    echo "  2. 测试图片上传触发转换"
    echo "  3. 监控CloudWatch告警状态"
    echo ""
    echo "🔍 查看配置:"
    echo "  aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN --region $AWS_REGION"
    echo "  aws lambda get-function-event-invoke-config --function-name $FUNCTION_NAME --region $AWS_REGION"
    echo "  aws cloudwatch describe-alarms --alarm-name-prefix lambda-$FUNCTION_NAME --region $AWS_REGION"
}

# 主函数
main() {
    echo "📢 SNS通知配置脚本"
    echo "===================="
    
    parse_arguments "$@"
    check_lambda_function
    create_sns_topic
    setup_email_subscription
    setup_sms_subscription
    setup_lambda_destination
    create_cloudwatch_alarms
    test_notification
    show_results
}

# 错误处理
trap 'print_error "配置过程中发生错误"; exit 1' ERR

# 运行主函数
main "$@"
