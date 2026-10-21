ENV["GKSwstype"] = "100" # Modo headless ativo para o Ubuntu Linux

using JuMP
using Gurobi
using Printf
using ProgressMeter

# Inclui os scripts organizados de dentro da subpasta src/
include("src/mhp_solver.jl")
include("src/io_utils.jl")

"""
    obter_info_hardware()
Varre os registros nativos do Linux e extrai o modelo da CPU, a RAM total e as especificacoes de threads.
"""
function obter_info_hardware()
    modelo_cpu = Sys.CPU_NAME
    if Sys.islinux() && isfile("/proc/cpuinfo")
        for linha in readlines("/proc/cpuinfo")
            if startswith(linha, "model name")
                partes = split(linha, ":")
                if length(partes) > 1
                    modelo_cpu = strip(partes[2])
                    break
                end
            end
        end
    end
    ram_gb = Sys.total_memory() / (1024^3)
    return (
        so = string(Sys.KERNEL, " ", Sys.ARCH),
        cpu = modelo_cpu,
        threads = Sys.CPU_THREADS,
        ram = @sprintf("%.2f GB", ram_gb),
        julia_v = string(VERSION)
    )
end

"""
    processar_conjunto(diretorio::String, f_relatorio, f_csv, p_bar, pasta_graficos::String; extensao::String=".txt")
Gerencia o laço iterativo em lote executando de forma automatica as rodadas lineares e inteiras via funcao generica.
"""
function processar_conjunto(diretorio::String, f_relatorio, f_csv, p_bar, pasta_graficos::String; extensao::String=".txt")
    if !isdir(diretorio) return end
    arquivos = sort(filter(f -> endswith(f, extensao), readdir(diretorio)))
    if isempty(arquivos) return end
    
    for arq in arquivos
        caminho = joinpath(diretorio, arq)
        try
            n, C = extensao == ".atsp" ? carregar_instancia_atsp(caminho) : carregar_instancia_txt(caminho)
            s, t = 1, n
            
            # Chamada da funcao generica para a Atividade 2 (Relaxacao Linear)
            res_lp = solve_mphp_model(C, is_integer=false, time_limit_sec=30.0)
            
            # Chamada da funcao generica para a Atividade 3 (Modelo Inteiro Binario Puro)
            res_ip = solve_mphp_model(C, is_integer=true, time_limit_sec=180.0)
            
            valido = validate_hamiltonian_path(n, res_ip.arcos, s, t)
            gap = (res_ip.custo != Inf && res_ip.custo > 0 && res_lp.custo != Inf) ? ((res_ip.custo - res_lp.custo) / res_ip.custo) * 100.0 : 0.0
            
            caminho_ordenado = Int[s]
            mapa_arcos = Dict(u => v for (u, v) in res_ip.arcos)
            atual = s
            while haskey(mapa_arcos, atual) && length(caminho_ordenado) < n
                prox = mapa_arcos[atual]
                push!(caminho_ordenado, prox)
                atual = prox
            end
            
            linha = @sprintf("%-32s | %-4d | %9.2f | %5.2fs | %9.2f | %5.2fs | %6.2f%% | %-6s | %-10s",
                             arq, n, res_lp.custo, res_lp.tempo, res_ip.custo, res_ip.tempo, gap, string(valido), string(res_ip.status))
            println(linha)
            println(f_relatorio, linha)
            
            vetor_rota_formatado = "[" * join(string.(caminho_ordenado), ", ") * "]"
            write(f_csv, "$arq;$n;$(res_lp.status);$(round(res_lp.custo, digits=2));$(round(res_lp.tempo, digits=4));$(res_ip.status);$(round(res_ip.custo, digits=2));$(round(res_ip.tempo, digits=4));$(round(gap, digits=2));$valido;$vetor_rota_formatado\n")
            
            if valido && length(caminho_ordenado) == n
                println(f_relatorio, " Rota: ", join(caminho_ordenado, " -> "))
                gerar_grafico_caminho(n, res_ip.arcos, arq, pasta_graficos)
            end
        catch e
            msg_erro = replace(sprint(showerror, e), "\n" => " ")
            linha_erro = @sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | ERRO: %s", arq, "-", "-", "-", "-", "-", "-", "-", msg_erro)
            println(linha_erro)
            println(f_relatorio, linha_erro)
            write(f_csv, "$arq;0;ERROR;N/A;N/A;ERROR;N/A;N/A;N/A;false;[]\n")
        end
        next!(p_bar)
    end
end

function main()
    hw = obter_info_hardware()
    saida_relatorio = "data/relatorio_pchm_gurobi.txt"
    saida_csv = "data/resultados_completos_pchm.csv"
    pasta_graficos = "graficos"
    
    if !isdir("data") mkdir("data") end
    
    dir_txt = isdir("instancias") ? "instancias" : (isdir("../instancias") ? "../instancias" : "")
    dir_atsp = isdir("instancias-professor") ? "instancias-professor" : (isdir("../instancias-professor") ? "../instancias-professor" : "")
    
    total_arquivos = 0
    if !isempty(dir_txt) total_arquivos += length(filter(f -> endswith(f, ".txt"), readdir(dir_txt))) end
    if !isempty(dir_atsp) total_arquivos += length(filter(f -> endswith(f, ".atsp"), readdir(dir_atsp))) end
    
    p_bar = Progress(total_arquivos, dt=0.5, desc="Processando: ", barlen=25)
    
    open(saida_relatorio, "w") do f_rel
        open(saida_csv, "w") do f_csv
            println(f_rel, "HARDWARE E AMBIENTE COMPUTACIONAL:")
            println(f_rel, " Processador: ", hw.cpu)
            println(f_rel, " Nucleos/Threads: ", hw.threads)
            println(f_rel, " Memoria RAM: ", hw.ram)
            println(f_rel, " Sistema Operacional: ", hw.so)
            println(f_rel, " Versao Julia: ", hw.julia_v)
            println(f_rel, " Solver: Gurobi Optimizer")
            println(f_rel, "")
            
            write(f_csv, "Instancia;N;Status_LP;Z_LP;Tempo_LP_s;Status_IP;Z_IP;Tempo_IP_s;GAP_Percentual;Caminho_Valido;Rota_Percorrida\n")
            println(@sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | %-10s", "Instancia", "n", "Z_LP", "T_LP", "Z_IP", "T_IP", "GAP", "Valido", "Status"))
            
            if !isempty(dir_txt) processar_conjunto(dir_txt, f_rel, f_csv, p_bar, pasta_graficos; extensao=".txt") end
            if !isempty(dir_atsp) processar_conjunto(dir_atsp, f_rel, f_csv, p_bar, pasta_graficos; extensao=".atsp") end
        end
    end
end

main()
