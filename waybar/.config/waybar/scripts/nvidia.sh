#!/bin/bash
# Temperatura + uso de la GPU NVIDIA para el módulo custom/nvidia de Waybar
read -r temp util <<< "$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits | tr -d ' ' | tr ',' ' ')"
printf '{"text":"%s°C %s%%","tooltip":"NVIDIA RTX 4060"}\n' "${temp:-?}" "${util:-?}"
