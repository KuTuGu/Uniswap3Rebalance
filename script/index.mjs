#!/usr/bin/env zx
const net = 'goerli'
const rpc = 'eth_goerli'

const debounceTime = 3
const intervalTime = 60

const exec = async () => {
    try {
        await $`forge script script/${net}.sol --via-ir --rpc-url https://rpc.ankr.com/${rpc} --silent`
        // debounce
        setTimeout(async () => {
            await $`forge script script/${net}.sol --via-ir --rpc-url https://rpc.ankr.com/${rpc} --silent --broadcast --slow`
        }, debounceTime * 60 * 1000)
    } catch {}
}

exec()
setInterval(exec, intervalTime * 60 * 1000)
