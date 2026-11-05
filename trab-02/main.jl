ENV["GKSwstype"] = "100"

using Plots
using Random
using Printf

include("grasp_solver.jl")
include("instancia_utils.jl")

# Executa a Heurística Inicial (Ativ. 1) e o GRASP com Union-Find (Ativ. 2) usando os parâmetros calibrados.
function execute_batch_processing()
    target_dir = "instancias-professor"
    if !ispath(target_dir) return end

    alpha_final, iter_final = load_chosen_parameters()
    checkpoints = sort(unique(vcat(filter(k -> k <= iter_final, [100, 250, 500, 750, 1000]), [iter_final])))
    println(@sprintf("Parametros calibrados: alpha = %.2f | iteracoes = %d", alpha_final, iter_final))

    atsp_files = sort(filter(f -> endswith(f, ".atsp"), readdir(target_dir)))
    if !ispath("data") mkpath("data") end
    csv_path = joinpath("data", "resultado_otimizacao.csv")
    times_path = joinpath("data", "tempos_checkpoints.csv")

    println(@sprintf("%-15s | %-3s | %10s | %8s | %10s | %8s | %9s | %-6s",
                     "Instancia", "n", "Z_Inicial", "T_Init", "Z_GRASP", "T_GRASP", "Melhoria", "Valido"))
    println(repeat("-", 88))

    open(csv_path, "w") do f_csv
        open(times_path, "w") do f_times
            write(f_csv, "Instancia;N;Z_Inicial;Tempo_Inicial_s;Z_GRASP;Tempo_GRASP_s;Melhoria_Percentual;Caminho_Valido;Rota_Percorrida\n")
            write(f_times, "Instancia;N;" * join(["T_$(k)_s" for k in checkpoints], ";") * "\n")

            for file in atsp_files
                n, costs = load_atsp_instance(joinpath(target_dir, file))

                # 1. Heurística Inicial (Atividade 1)
                t_start_init = time()
                initial_route = run_initial_heuristic(n, costs)
                time_init = time() - t_start_init
                z_init = calculate_route_cost(initial_route, costs)

                # 2. GRASP com os parâmetros calibrados (Atividade 2)
                Random.seed!(42)
                t_start_grasp = time()
                best_route, best_cost_global, history = run_grasp_metaheuristic(n, costs, iter_final, alpha_final; checkpoints=checkpoints)
                time_grasp = time() - t_start_grasp

                generate_path_plot(n, best_route, file, "data/plots")

                melhoria = z_init > 0 ? ((z_init - best_cost_global) / z_init) * 100.0 : 0.0
                is_valid = (length(best_route) == n && length(unique(best_route)) == n && best_route[1] == 1 && best_route[end] == n)
                formatted_vector = "[" * join(best_route, ", ") * "]"

                println(@sprintf("%-15s | %-3d | %10.2f | %7.4fs | %10.2f | %7.4fs | %8.2f%% | %-6s",
                                 file, n, z_init, time_init, best_cost_global, time_grasp, melhoria, string(is_valid)))

                write(f_csv, "$file;$n;$(round(z_init, digits=2));$(round(time_init, digits=6));$(round(best_cost_global, digits=2));$(round(time_grasp, digits=4));$(round(melhoria, digits=2));$is_valid;$formatted_vector\n")
                write(f_times, "$file;$n;" * join([string(round(history[k][2], digits=4)) for k in checkpoints], ";") * "\n")
            end
        end
    end

    println(repeat("-", 88))
    println("Processamento concluido! Resultados salvos em data/resultado_otimizacao.csv e data/tempos_checkpoints.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
    execute_batch_processing()
end
