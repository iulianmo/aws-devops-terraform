#!/bin/bash -xe

cd main

terraform_init() {
    cd $1
    terraform init -reconfigure
    terraform apply -auto-approve
    cd ..
}

deploy_vpc() {
    terraform_init vpc
}

deploy_ecs() {
    terraform_init ecs

}

deploy_pipeline() {
    terraform_init pipeline
}

deploy_all() {
    deploy_vpc
    deploy_ecs
    deploy_pipeline
}

deploy_all