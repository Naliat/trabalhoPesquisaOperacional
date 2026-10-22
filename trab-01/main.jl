ENV["GKSwstype"] = "100" # Modo headless ativo para o Ubuntu Linux

using JuMP
using Gurobi
using Printf
using ProgressMeter

# Inclui os scripts organizados de dentro da subpasta src/
include("src/mhp_solver.jl")
include("src/io_utils.jl")

"""
    get_hardware_info()

Varre os registros nativos do Linux e extrai o modelo da CPU, a RAM total e as especificacoes de threads.
"""
function get_hardware_info()
    cpu_model = Sys.CPU_NAME
    if Sys.islinux() && isfile("/proc/cpuinfo")
        for line in readlines("/proc/cpuinfo")
            if startswith(line, "model name")
                parts = split(line, ":")
                if length(parts) > 1
                    cpu_model = strip(parts[2])
                    break
                end
            end
        end
    end
    ram_gb = Sys.total_memory() / (1024^3)
    return (
        os = string(Sys.KERNEL, " ", Sys.ARCH),
        cpu = cpu_model,
        threads = Sys.CPU_THREADS,
        ram = @sprintf("%.2f GB", ram_gb),
        julia_v = string(VERSION)
    )
end

"""
    process_batch(directory::String, f_report, f_csv, p_bar, graphics_folder::String; extension::String=".txt")

Gerencia o laço iterativo em lote executando de forma automatica as rodadas lineares e inteiras via funcao generica.
"""
function process_batch(directory::String, f_report, f_csv, p_bar, graphics_folder::String; extension::String=".txt")
    if !isdir(directory) return end
    files = sort(filter(f -> endswith(f, extension), readdir(directory)))
    if isempty(files) return end
    
    for file in files
        path = joinpath(directory, file)
        try
            # Nomes atualizados para as chamadas em inglês que estão no io_utils.jl
            n, C = extension == ".atsp" ? load_atsp_instance(path) : load_txt_instance(path)
            s, t = 1, n
            
            # Chamada da funcao generica para a Atividade 2 (Relaxacao Linear)
            res_lp = solve_mphp_model(C, is_integer=false, time_limit_sec=30.0)
            
            # Chamada da funcao generica para a Atividade 3 (Modelo Inteiro Binario Puro)
            res_ip = solve_mphp_model(C, is_integer=true, time_limit_sec=180.0)
            
            valid = validate_hamiltonian_path(n, res_ip.arcos, s, t)
            gap = (res_ip.custo != Inf && res_ip.custo > 0 && res_lp.custo != Inf) ? ((res_ip.custo - res_lp.custo) / res_ip.custo) * 100.0 : 0.0
            
            ordered_path = Int[s]
            arcs_map = Dict(u => v for (u, v) in res_ip.arcos)
            current = s
            while haskey(arcs_map, current) && length(ordered_path) < n
                next_node = arcs_map[current]
                push!(ordered_path, next_node)
                current = next_node
            end
            
            line = @sprintf("%-32s | %-4d | %9.2f | %5.2fs | %9.2f | %5.2fs | %6.2f%% | %-6s | %-10s",
                             file, n, res_lp.custo, res_lp.tempo, res_ip.custo, res_ip.tempo, gap, string(valid), string(res_ip.status))
            println(line)
            println(f_report, line)
            
            formatted_route_vector = "[" * join(string.(ordered_path), ", ") * "]"
            write(f_csv, "$file;$n;$(res_lp.status);$(round(res_lp.custo, digits=2));$(round(res_lp.tempo, digits=4));$(res_ip.status);$(round(res_ip.custo, digits=2));$(round(res_ip.tempo, digits=4));$(round(gap, digits=2));$valid;$formatted_route_vector\n")
            
            if valid && length(ordered_path) == n
                println(f_report, " Rota: ", join(ordered_path, " -> "))
                # Nome atualizado para a geração de gráficos que está no io_utils.jl
                generate_path_plot(n, res_ip.arcos, file, graphics_folder)
            end
        catch e
            error_msg = replace(sprint(showerror, e), "\n" => " ")
            error_line = @sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | ERRO: %s", file, "-", "-", "-", "-", "-", "-", "-", error_msg)
            println(error_line)
            println(f_report, error_line)
            write(f_csv, "$file;0;ERROR;N/A;N/A;ERROR;N/A;N/A;N/A;false;[]\n")
        end
        next!(p_bar)
    end
end

function main()
    hw = get_hardware_info()
    report_output = "data/relatorio_pchm_gurobi.txt"
    csv_output = "data/resultados_completos_pchm.csv"
    graphics_folder = "graficos"
    
    if !isdir("data") mkdir("data") end
    
    txt_dir = isdir("instancias") ? "instancias" : (isdir("../instancias") ? "../instancias" : "")
    atsp_dir = isdir("instancias-professor") ? "instancias-professor" : (isdir("../instancias-professor") ? "../instancias-professor" : "")
    
    total_files = 0
    if !isempty(txt_dir) total_files += length(filter(f -> endswith(f, ".txt"), readdir(txt_dir))) end
    if !isempty(atsp_dir) total_files += length(filter(f -> endswith(f, ".atsp"), readdir(atsp_dir))) end
    
    p_bar = Progress(total_files, dt=0.5, desc="Processando: ", barlen=25)
    
    open(report_output, "w") do f_rel
        open(csv_output, "w") do f_csv
            println(f_rel, "HARDWARE E AMBIENTE COMPUTACIONAL:")
            println(f_rel, " Processador: ", hw.cpu)
            println(f_rel, " Nucleos/Threads: ", hw.threads)
            println(f_rel, " Memoria RAM: ", hw.ram)
            println(f_rel, " Sistema Operacional: ", hw.os) # Alterado de hw.so para hw.os para corrigir o erro
            println(f_rel, " Versao Julia: ", hw.julia_v)
            println(f_rel, " Solver: Gurobi Optimizer")
            println(f_rel, "")
            
            write(f_csv, "Instancia;N;Status_LP;Z_LP;Tempo_LP_s;Status_IP;Z_IP;Tempo_IP_s;GAP_Percentual;Caminho_Valido;Rota_Percorrida\n")
            println(@sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | %-10s", "Instancia", "n", "Z_LP", "T_LP", "Z_IP", "T_IP", "GAP", "Valido", "Status"))
            
            if !isempty(txt_dir) process_batch(txt_dir, f_rel, f_csv, p_bar, graphics_folder; extension=".txt") end
            if !isempty(atsp_dir) process_batch(atsp_dir, f_rel, f_csv, p_bar, graphics_folder; extension=".atsp") end
        end
    end
end

main()
