using JuMP
using Gurobi
using Printf
using ProgressMeter

include("src/mhp_solver.jl")
include("src/io_utils.jl")

# Processa em lote as instâncias de um diretório, medindo tempos, custos e validando as rotas.
function process_batch(directory::String, f_report, f_csv, p_bar, graphics_folder::String; extension::String=".txt")
    if !isdir(directory) return end
    files = sort(filter(f -> endswith(f, extension), readdir(directory)))
    if isempty(files) return end
    
    for file in files
        path = joinpath(directory, file)
        try
            b_load = benchmark_stage(() -> (extension == ".atsp" ? load_atsp_instance(path) : load_txt_instance(path)))
            n, C = b_load.result
            t_load, ram_load = b_load.time_sec, b_load.gc_ram_mb
            s, t = 1, n
            
            b_lp = benchmark_stage(() -> solve_mphp_model(C, is_integer=false, time_limit_sec=30.0))
            res_lp = b_lp.result
            t_lp, ram_lp = b_lp.time_sec, b_lp.gc_ram_mb
            
            b_ip = benchmark_stage(() -> solve_mphp_model(C, is_integer=true, time_limit_sec=180.0))
            res_ip = b_ip.result
            t_ip, ram_ip = b_ip.time_sec, b_ip.gc_ram_mb
            
            b_val = benchmark_stage(() -> validate_hamiltonian_path(n, res_ip.arcos, s, t))
            valid = b_val.result
            t_val, ram_val = b_val.time_sec, b_val.gc_ram_mb
            
            gap = (res_ip.custo != Inf && res_ip.custo > 0 && res_lp.custo != Inf) ? 
                  ((res_ip.custo - res_lp.custo) / res_ip.custo) * 100.0 : 0.0
            
            ordered_path = Int[s]
            arcs_map = Dict(u => v for (u, v) in res_ip.arcos)
            current = s
            while haskey(arcs_map, current) && length(ordered_path) < n
                next_node = arcs_map[current]
                push!(ordered_path, next_node)
                current = next_node
            end
            
            line = @sprintf("%-30s | %-3d | %9.2f | %5.2fs | %6.2fMB | %9.2f | %6.2fs | %6.2fMB | %6.2f%% | %-5s | %-10s",
                             file, n, res_lp.custo, t_lp, ram_lp, res_ip.custo, t_ip, ram_ip, gap, string(valid), string(res_ip.status))
            println(line)
            println(f_report, line)
            
            if !isempty(ordered_path) && res_ip.custo != Inf
                route_header = "  [$file] Caminho Hamiltoniano (Origem: $s -> Destino: $t | Nós visitados: $(length(ordered_path))/$n):"
                route_body   = "    " * join(ordered_path, " -> ")
                
                println(f_report, route_header)
                println(f_report, route_body)
                println(f_report, "")
                
                println(route_header)
                println(route_body)
            end

            formatted_route_vector = "[" * join(string.(ordered_path), ", ") * "]"
            write(f_csv, "$file;$n;$(res_lp.status);$(round(res_lp.custo, digits=2));$(round(t_lp, digits=4));$(round(ram_lp, digits=2));$(res_ip.status);$(round(res_ip.custo, digits=2));$(round(t_ip, digits=4));$(round(ram_ip, digits=2));$(round(t_load, digits=4));$(round(t_val, digits=4));$(round(gap, digits=2));$valid;$formatted_route_vector\n")
            
            if valid && length(ordered_path) == n
                generate_path_plot(n, res_ip.arcos, file, graphics_folder)
            end
        catch e
            error_msg = replace(sprint(showerror, e), "\n" => " ")
            error_line = @sprintf("%-30s | %-3s | %-9s | %-6s | %-8s | %-9s | %-7s | %-8s | %-7s | %-5s | ERRO: %s", 
                                  file, "-", "-", "-", "-", "-", "-", "-", "-", "-", error_msg)
            println(error_line)
            println(f_report, error_line)
            write(f_csv, "$file;0;ERROR;N/A;N/A;N/A;ERROR;N/A;N/A;N/A;N/A;N/A;N/A;false;[]\n")
        end
        next!(p_bar)
    end
end

# Função principal que orquestra a execução das instâncias e geração dos relatórios.
function main()
    hw = get_hardware_info()
    report_output = "data/relatorio_pchm_gurobi.txt"
    csv_output = "data/resultados_completos_pchm.csv"
    graphics_folder = "graficos"
    
    if !isdir("data") mkpath("data") end
    if !isdir(graphics_folder) mkpath(graphics_folder) end
    
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
            println(f_rel, " Memoria RAM Instalada: ", hw.ram)
            println(f_rel, " Sistema Operacional: ", hw.os)
            println(f_rel, " Versao Julia: ", hw.julia_v)
            println(f_rel, " Solver: Gurobi Optimizer")
            println(f_rel, "")
            
            write(f_csv, "Instancia;N;Status_LP;Z_LP;Tempo_LP_s;RAM_LP_MB;Status_IP;Z_IP;Tempo_IP_s;RAM_IP_MB;Tempo_Load_s;Tempo_Val_s;GAP_Percentual;Caminho_Valido;Rota_Percorrida\n")
            
            println(@sprintf("%-30s | %-3s | %-9s | %-6s | %-8s | %-9s | %-7s | %-8s | %-7s | %-5s | %-10s", 
                             "Instancia", "n", "Z_LP", "T_LP", "RAM_LP", "Z_IP", "T_IP", "RAM_IP", "GAP", "Val", "Status"))
            println(repeat("-", 125))
            
            if !isempty(txt_dir) process_batch(txt_dir, f_rel, f_csv, p_bar, graphics_folder; extension=".txt") end
            if !isempty(atsp_dir) process_batch(atsp_dir, f_rel, f_csv, p_bar, graphics_folder; extension=".atsp") end
        end
    end
end

main()
