#!/bin/bash

# S3图片自动转WebP Lambda系统一键部署脚本
# 版本: v2.0
# 更新日期: 2025-08-27

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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
    echo "S3图片自动转WebP Lambda系统部署脚本"
    echo ""
    echo "用法:"
    echo "  $0 [S3桶名] [AWS区域] [Lambda函数名]"
    echo ""
    echo "参数:"
    echo "  S3桶名        存储图片的S3桶名称 (必需)"
    echo "  AWS区域       部署的AWS区域 (默认: us-west-2)"
    echo "  Lambda函数名  Lambda函数名称 (默认: image-to-webp)"
    echo ""
    echo "示例:"
    echo "  $0 my-image-bucket"
    echo "  $0 my-image-bucket us-east-1"
    echo "  $0 my-image-bucket us-west-2 my-webp-converter"
    echo ""
    echo "环境要求:"
    echo "  - AWS CLI 已配置"
    echo "  - 具有管理员权限"
    echo "  - bash shell环境"
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖..."
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI 未安装，请先安装 AWS CLI"
        exit 1
    fi
    
    # 检查AWS配置
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI 未配置或权限不足，请运行 'aws configure'"
        exit 1
    fi
    
    # 检查zip命令
    if ! command -v zip &> /dev/null; then
        print_error "zip 命令未找到，请安装 zip"
        exit 1
    fi
    
    # 验证AWS权限
    print_info "验证AWS权限..."
    local test_result=0
    
    # 测试Lambda权限
    aws lambda list-functions --max-items 1 &>/dev/null || test_result=1
    
    # 测试S3权限
    aws s3 ls &>/dev/null || test_result=1
    
    # 测试IAM权限
    aws iam list-roles --max-items 1 &>/dev/null || test_result=1
    
    if [ $test_result -ne 0 ]; then
        print_error "AWS权限不足，需要Lambda、S3、IAM的管理权限"
        exit 1
    fi
    
    print_success "依赖检查通过"
}

# 获取参数
get_parameters() {
    # S3桶名
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
    
    # AWS区域
    if [ -z "$2" ]; then
        AWS_REGION="us-west-2"
        print_info "使用默认区域: $AWS_REGION"
    else
        AWS_REGION="$2"
    fi
    
    # Lambda函数名
    if [ -z "$3" ]; then
        FUNCTION_NAME="image-to-webp"
        print_info "使用默认函数名: $FUNCTION_NAME"
    else
        FUNCTION_NAME="$3"
    fi
    
    # 获取账户ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$ACCOUNT_ID" ]; then
        print_error "无法获取AWS账户ID，请检查AWS CLI配置"
        exit 1
    fi
    
    print_info "部署参数:"
    echo "  S3桶名: $BUCKET_NAME"
    echo "  AWS区域: $AWS_REGION"
    echo "  Lambda函数名: $FUNCTION_NAME"
    echo "  AWS账户ID: $ACCOUNT_ID"
}

# 检查S3桶是否存在
check_s3_bucket() {
    print_info "检查S3桶: $BUCKET_NAME"
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
        print_success "S3桶存在: $BUCKET_NAME"
    else
        print_warning "S3桶不存在，正在创建..."
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
        print_success "S3桶创建成功: $BUCKET_NAME"
    fi
}

# 创建IAM角色
create_iam_role() {
    print_info "创建IAM角色..."
    
    ROLE_NAME="${FUNCTION_NAME}-role"
    
    # 创建信任策略
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # 检查角色是否存在
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_warning "IAM角色已存在: $ROLE_NAME"
    else
        # 创建IAM角色
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file://trust-policy.json \
            --region "$AWS_REGION"
        print_success "IAM角色创建成功: $ROLE_NAME"
    fi
    
    # 附加基础执行权限
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # 创建S3访问策略
    POLICY_NAME="${FUNCTION_NAME}-s3-policy"
    cat > s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

    # 检查策略是否存在
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        print_warning "S3策略已存在: $POLICY_NAME"
    else
        # 创建并附加S3策略
        aws iam create-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document file://s3-policy.json
        print_success "S3策略创建成功: $POLICY_NAME"
    fi
    
    # 附加S3策略
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    
    # 等待角色生效
    print_info "等待IAM角色生效..."
    sleep 10
    
    print_success "IAM角色配置完成"
    
    # 清理临时文件
    rm -f trust-policy.json s3-policy.json
}

# 创建Lambda部署包
create_lambda_package() {
    print_info "创建Lambda部署包..."
    
    # 清理之前的构建
    rm -rf lambda_package
    rm -f lambda_function.zip
    
    # 创建构建目录
    mkdir -p lambda_package
    
    # 检查lambda_function.py是否存在
    if [ ! -f "lambda_function.py" ]; then
        print_error "lambda_function.py 文件不存在，请确保文件在当前目录"
        exit 1
    fi
    
    # 复制Lambda函数代码
    cp lambda_function.py lambda_package/
    
    # 创建部署包
    cd lambda_package
    zip -r ../lambda_function.zip .
    cd ..
    
    print_success "Lambda部署包创建完成: lambda_function.zip"
}

# 获取Pillow Layer ARN
get_pillow_layer_arn() {
    print_info "获取Pillow Layer ARN..."
    
    # 使用AWS社区提供的Pillow Layer
    case "$AWS_REGION" in
        us-east-1)
            PILLOW_LAYER_ARN="arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p39-pillow:1"
            ;;
        us-west-2)
            PILLOW_LAYER_ARN="arn:aws:lambda:us-west-2:770693421928:layer:Klayers-p39-pillow:1"
            ;;
        eu-west-1)
            PILLOW_LAYER_ARN="arn:aws:lambda:eu-west-1:770693421928:layer:Klayers-p39-pillow:1"
            ;;
        ap-southeast-1)
            PILLOW_LAYER_ARN="arn:aws:lambda:ap-southeast-1:770693421928:layer:Klayers-p39-pillow:1"
            ;;
        *)
            print_warning "区域 $AWS_REGION 可能不支持预构建的Pillow Layer"
            PILLOW_LAYER_ARN="arn:aws:lambda:us-west-2:770693421928:layer:Klayers-p39-pillow:1"
            ;;
    esac
    
    print_success "Pillow Layer ARN: $PILLOW_LAYER_ARN"
}

# 创建或更新Lambda函数
create_lambda_function() {
    print_info "创建Lambda函数..."
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FUNCTION_NAME}-role"
    
    # 检查函数是否存在
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_warning "Lambda函数已存在，正在更新..."
        
        # 更新函数代码
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file fileb://lambda_function.zip \
            --region "$AWS_REGION"
        
        # 更新函数配置
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.9 \
            --handler lambda_function.lambda_handler \
            --role "$ROLE_ARN" \
            --timeout 300 \
            --memory-size 512 \
            --layers "$PILLOW_LAYER_ARN" \
            --environment Variables='{WEBP_QUALITY=85,OUTPUT_PREFIX="",DELETE_ORIGINAL=false}' \
            --region "$AWS_REGION"
        
        print_success "Lambda函数更新完成"
    else
        # 创建新函数
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda_function.zip \
            --timeout 300 \
            --memory-size 512 \
            --layers "$PILLOW_LAYER_ARN" \
            --environment Variables='{WEBP_QUALITY=85,OUTPUT_PREFIX="",DELETE_ORIGINAL=false}' \
            --region "$AWS_REGION"
        
        print_success "Lambda函数创建完成"
    fi
    
    # 等待函数就绪
    print_info "等待Lambda函数就绪..."
    aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
}

# 配置S3事件通知
configure_s3_events() {
    print_info "配置S3事件通知..."
    
    LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
    
    # 给Lambda函数S3调用权限
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
        --statement-id s3-trigger-permission \
        --region "$AWS_REGION" 2>/dev/null || print_warning "权限可能已存在"
    
    # 创建S3事件通知配置
    cat > s3-notification.json << EOF
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

    # 配置S3事件通知
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration file://s3-notification.json \
        --region "$AWS_REGION"
    
    print_success "S3事件通知配置完成"
    
    # 清理临时文件
    rm -f s3-notification.json
}

# 测试部署
test_deployment() {
    print_info "测试部署..."
    
    # 创建测试图片（实际上是文本文件，但用于测试触发）
    echo "This is a test file for Lambda trigger" > test-image.png
    
    # 上传测试文件
    aws s3 cp test-image.png "s3://${BUCKET_NAME}/test-image.png" --region "$AWS_REGION"
    
    print_info "测试文件已上传，请等待10秒后查看日志..."
    sleep 10
    
    # 检查日志
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${FUNCTION_NAME}" --region "$AWS_REGION" | grep -q "logGroupName"; then
        print_success "Lambda函数已被触发，可以查看CloudWatch日志"
        print_info "查看日志命令: aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
    else
        print_warning "未检测到Lambda执行日志，请检查配置"
    fi
    
    # 清理测试文件
    rm -f test-image.png
    aws s3 rm "s3://${BUCKET_NAME}/test-image.png" --region "$AWS_REGION" 2>/dev/null || true
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    rm -f lambda_function.zip
    rm -rf lambda_package
    print_success "清理完成"
}

# 显示部署结果
show_results() {
    echo ""
    print_success "🎉 部署完成！"
    echo ""
    echo "📋 部署信息:"
    echo "  S3桶名: $BUCKET_NAME"
    echo "  Lambda函数: $FUNCTION_NAME"
    echo "  AWS区域: $AWS_REGION"
    echo "  函数ARN: arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
    echo ""
    echo "🎯 使用方法:"
    echo "  1. 上传图片到S3桶: aws s3 cp image.png s3://${BUCKET_NAME}/"
    echo "  2. 查看转换结果: aws s3 ls s3://${BUCKET_NAME}/ --recursive | grep webp"
    echo "  3. 查看日志: aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
    echo ""
    echo "⚙️ 支持的格式: PNG, JPG, JPEG, BMP, TIFF, TIF"
    echo "📊 输出格式: WebP (质量85%)"
    echo ""
    echo "🔧 配置环境变量:"
    echo "  aws lambda update-function-configuration \\"
    echo "    --function-name ${FUNCTION_NAME} \\"
    echo "    --environment Variables='{WEBP_QUALITY=90}' \\"
    echo "    --region ${AWS_REGION}"
    echo ""
    echo "📢 配置失败通知 (可选):"
    echo "  1. 创建SNS主题:"
    echo "     aws sns create-topic --name lambda-image-conversion-failures --region ${AWS_REGION}"
    echo ""
    echo "  2. 订阅邮件通知:"
    echo "     TOPIC_ARN=\$(aws sns list-topics --query 'Topics[?contains(TopicArn, \`lambda-image-conversion-failures\`)].TopicArn' --output text --region ${AWS_REGION})"
    echo "     aws sns subscribe --topic-arn \$TOPIC_ARN --protocol email --notification-endpoint your-email@example.com --region ${AWS_REGION}"
    echo ""
    echo "  3. 配置Lambda失败目标:"
    echo "     aws lambda put-function-event-invoke-config \\"
    echo "       --function-name ${FUNCTION_NAME} \\"
    echo "       --destination-config '{\"OnFailure\":{\"Destination\":\"'\$TOPIC_ARN'\"}}' \\"
    echo "       --region ${AWS_REGION}"
    echo ""
    echo "📖 详细文档: 查看 README.md 中的监控和日志部分"
}

# 主函数
main() {
    echo "🚀 S3图片自动转WebP Lambda系统部署脚本"
    echo "================================================"
    
    # 检查帮助参数
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # 执行部署步骤
    check_dependencies
    get_parameters "$@"
    check_s3_bucket
    create_iam_role
    create_lambda_package
    get_pillow_layer_arn
    create_lambda_function
    configure_s3_events
    test_deployment
    cleanup
    show_results
}

# 错误处理
trap 'print_error "部署过程中发生错误，请检查上面的错误信息"; cleanup; exit 1' ERR

# 运行主函数
main "$@"
