ENV["GKSwstype"] = "100" # Modo headless ativo para o Ubuntu Linux

using JuMP
using GLPK

# Inclui os scripts organizados de dentro da subpasta src/
include("src/mhp_solver.jl")
include("src/io_utils.jl")

function run_batch_pipeline(instances_folder::String, data_folder::String, output_csv::String, plots_folder::String)
    println("\n" * "="^80)
    println(" UFC QUIXADA - BATCH PROCESSING PIPELINE (TSPLIB CONTEXT)")
    println("="^80)
    
    if !ispath(instances_folder) error("A pasta de instancias '$instances_folder' nao foi encontrada!") end
    if !ispath(data_folder) mkdir(data_folder) end 
    
    files = sort(filter(f -> endswith(f, ".atsp"), readdir(instances_folder)))
    csv_full_path = joinpath(data_folder, output_csv)

    open(csv_full_path, "w") do io
        write(io, "Instance;Leitura_Status;Otimizacao_Status;Custo_Total;Caminho_Valido\n")
        
        for file in files
            println("   Analizando arquivo: $file")
            file_path = joinpath(instances_folder, file)
            read_status, optimize_status, total_cost, valid_path = "SUCESSO", "N/A", "N/A", "N/A"
            
            try
                n, cost_matrix = read_tsplib_instance(file_path)
                
                # Chamada do modelo matemático traduzido com limitador de 3 minutos
                obj_value, active_arcs, solver_status = solve_mphp_mtz(cost_matrix, is_integer=true, time_limit_sec=180)
                optimize_status = string(solver_status)
                
                if solver_status == OPTIMAL || solver_status == TIME_LIMIT
                    total_cost = string(round(obj_value, digits=2))
                    is_valid = validate_hamiltonian_path(active_arcs, n, 1, n)
                    valid_path = string(is_valid)
                    
                    println("     [SUCESSO] Concluido ($solver_status)! N=$n | Custo=$total_cost | Valido=$valid_path")
                    generate_route_plot(n, active_arcs, file, plots_folder)
                else
                    println("     [AVISO] Solver interrompido. Status: $solver_status")
                end
            catch e
                read_status = "ERRO_FORMATO"
                println("     [ERRO] Falha critica de processamento: ", sprint(showerror, e))
            end
            write(io, "$file;$read_status;$optimize_status;$total_cost;$valid_path\n")
        end
    end
    println("="^80 * "\nPipeline executado. Planilha gerada em: $csv_full_path\n")
end

# Dispara a rodada total salvando a tabela consolidada dentro da pasta data/
run_batch_pipeline("instancias-professor", "data", "resultados_cenarios_completos.csv", "graficos")
