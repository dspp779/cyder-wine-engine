/* Unmodified Wine loader patch sites; unrelated code omitted. */

}


/***********************************************************************
 *	find_builtin_without_file
 *

/* unrelated loader code omitted */

    *pwm = NULL;
    *redirected = FALSE;
    nt_name->Buffer = NULL;

    if (!contains_path( libname ))
    {

/* unrelated loader code omitted */

            InitializeListHead( &hash_table[i] );

        init_user_process_params();
        load_global_options();
        version_init();
        open_known_dll_ntdir();
